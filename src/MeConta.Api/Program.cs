using System.Text.Json.Serialization;
using MeConta.Api.Adapters;
using MeConta.Api.Configuracao;
using MeConta.Application.Adapters;
using MeConta.Infrastructure;
using MeConta.Infrastructure.Persistencia;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Scalar.AspNetCore;

namespace MeConta.Api;

/// <summary>
/// Ponto de entrada da Web API do Me Conta.
/// A classe é "partial" para que os testes de integração possam subir a API com WebApplicationFactory.
/// </summary>
public partial class Program
{
    public static async Task Main(string[] args)
    {
        WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

        // No servidor Linux, os segredos (ex.: Gemini:ChaveApi) chegam cifrados pelo systemd e são entregues
        // decifrados só para este processo, um arquivo por chave, na pasta $CREDENTIALS_DIRECTORY.
        // Fora do servidor a variável não existe e nada muda (no desenvolvimento valem os user-secrets).
        string? pastaDeSegredos = Environment.GetEnvironmentVariable("CREDENTIALS_DIRECTORY");
        if (!string.IsNullOrEmpty(pastaDeSegredos))
        {
            builder.Configuration.AddKeyPerFile(pastaDeSegredos, optional: true);
        }

        // Banco, repositórios e adapters (camada Infrastructure).
        ProvedorDeBanco provedor = builder.Configuration.GetValue("Banco:Provedor", ProvedorDeBanco.SqlServer);
        string connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? string.Empty;
        string pastaDeArquivos = builder.Configuration["Armazenamento:Pasta"]
            ?? Path.Combine(builder.Environment.ContentRootPath, "storage");
        builder.Services.AdicionarInfraestrutura(provedor, connectionString, pastaDeArquivos);

        // IA da remediação (Gemini, chave em user-secrets) e relatórios da auditoria do código (Semgrep).
        string pastaDosRelatorios = builder.Configuration["Seguranca:PastaDosRelatorios"]
            ?? Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, "..", "..", "seguranca", "relatorios"));
        builder.Services.AdicionarRemediacao(builder.Configuration, pastaDosRelatorios);

        // Casos de uso (camada Application) e regras do domínio.
        builder.Services.AdicionarAplicacao(builder.Configuration["Privacidade:ArquivoDeRegras"]);
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddScoped<IUsuarioAtual, UsuarioAtualHttp>();

        // Login com ASP.NET Identity: /api/v1/auth/register e /api/v1/auth/login devolvem token Bearer.
        builder.Services.AddAuthorization();
        builder.Services
            .AddIdentityApiEndpoints<IdentityUser>()
            .AddEntityFrameworkStores<AppDbContext>();

        builder.Services
            .AddControllers(options =>
            {
                // Mantém o sufixo "Async" no nome das ações, para o CreatedAtAction encontrar a rota.
                options.SuppressAsyncSuffixInActionNames = false;
            })
            .AddJsonOptions(options =>
                options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));

        // Erros viram ProblemDetails (RFC 9457) com a mensagem da regra de negócio.
        builder.Services.AddProblemDetails();
        builder.Services.AddExceptionHandler<TratadorDeExcecoes>();

        // Documentação automática: um documento OpenAPI, exibido no Swagger UI e no Scalar.
        builder.Services.AddOpenApi(options => options.AddDocumentTransformer<DocumentacaoOpenApi>());

        // Limite de pedidos por endereço nas rotas abertas do painel e nas que chamam a IA:
        // protege a cota do plano gratuito do Gemini e o banco de quem tentar derrubar o painel.
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.AddPolicy(LimitesDeUso.Painel, contexto => LimitesDeUso.PorEndereco(contexto, LimitesDeUso.PedidosDoPainelPorMinuto));
            options.AddPolicy(LimitesDeUso.Ia, contexto => LimitesDeUso.PorEndereco(contexto, LimitesDeUso.PedidosDaIaPorMinuto));
        });

        builder.Services.AddHealthChecks().AddDbContextCheck<AppDbContext>("banco");

        // Libera chamadas do app rodando no navegador (Expo Web) durante o desenvolvimento.
        builder.Services.AddCors(options => options.AddPolicy(
            "app",
            policy => policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

        WebApplication app = builder.Build();

        // Atrás do nginx (servidor Linux), o IP real do cliente chega no X-Forwarded-For. Só é aceito quando
        // a conexão vem do próprio servidor (127.0.0.1/::1), então ninguém de fora consegue forjar o endereço.
        // Sem isso, o limite de requisições por IP trataria todos os usuários como um só (127.0.0.1).
        app.UseForwardedHeaders(new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
        });

        app.UseExceptionHandler();

        // Painel executivo Risco Cidadão: página estática em /risco-cidadao/ (wwwroot), com cabeçalhos de segurança.
        app.UseDefaultFiles();
        app.UseStaticFiles(new StaticFileOptions { OnPrepareResponse = CabecalhosDoPainel.Aplicar });

        app.UseCors("app");
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRateLimiter();

        app.MapOpenApi();
        app.UseSwaggerUI(options =>
        {
            options.SwaggerEndpoint("/openapi/v1.json", "Me Conta API v1");
            options.DocumentTitle = "Me Conta API";
        });
        app.MapScalarApiReference(options => options.WithTitle("Me Conta API"));

        app.MapGroup("/api/v1/auth")
            .MapIdentityApi<IdentityUser>()
            .WithTags("Autenticação");
        app.MapControllers();
        app.MapHealthChecks("/health");

        bool dadosDeDemonstracao = builder.Configuration.GetValue("Banco:DadosDeDemonstracao", false);
        bool paginasDoFiltro = builder.Configuration.GetValue("Banco:PaginasDoFiltroDePrivacidade", false);
        await DbInicializador.InicializarAsync(app.Services, dadosDeDemonstracao, paginasDoFiltro);

        await app.RunAsync();
    }
}
