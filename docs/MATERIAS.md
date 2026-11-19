# O que cada matéria faz nesta API

O Me Conta é uma solução só, dividida em partes. Esta API é o centro: o app, o porta-retrato e o servidor Linux conversam com ela, e o módulo de privacidade roda dentro dela. Este documento mostra, matéria por matéria, **qual é a parte dela no Me Conta** e **onde, dentro deste repositório, cada item de entrega é atendido**.

[← Voltar ao README](../README.md)

## Visão geral

| Matéria | Papel no Me Conta | Onde está | Situação |
| --- | --- | --- | --- |
| [C# Software Development](#c-software-development) | Web API em .NET 10 com domínio orientado a objetos, EF Core e LINQ | Este repositório (`src/`, `tests/`) | ✅ Pronta |
| [SOA e Web Services](#soa-e-web-services) | Serviços REST que o app e o porta-retrato consomem, com banco, migrações e documentação automática | Este repositório (`src/`, `tests/`, `docs/`) | ✅ Pronta |
| [Physical Computing (IoT)](#physical-computing-iot) | Porta-retrato com ESP32: acende quando chega pergunta e tem o botão "quero contar" | Pasta [`iot/`](../iot/README.md) (circuito, firmware, ponte Node-RED, evidências) e rotas do aparelho nesta API | ✅ Pronta (falta o link do vídeo) |
| [Cybersecurity](#cybersecurity) | Filtro de dados pessoais antes de publicar no mapa do bairro, taint analysis e painel "Risco Cidadão" | Módulo `MeConta.Privacidade` dentro desta API | 🟡 Motor de PII, mapa do bairro e taint analysis prontos; IA e painel em andamento |
| [Operating Systems](#operating-systems) | VM Linux que roda esta API, com monitoramento e logs de auditoria | Pasta [`linux/`](../linux/README.md) (provisionamento em Bash, serviços systemd, monitor, auditoria, teste de falha) | ✅ Pronto |
| [Testing, Compliance & QA](#testing-compliance--qa) | Backlog com critérios de aceite e casos de teste no Azure DevOps | Azure DevOps; nesta API, os casos que rodam pelo Swagger | ✅ Pronta |
| [Mobile](#mobile) | App Expo que a neta usa: perguntar, enviar pelo WhatsApp e montar o caderno | Repositório do app; consome esta API | 🟡 Em andamento |
| [IA & ML](#ia--ml) | Modelo com dados reais da PNAD TIC que aponta quais idosos têm mais chance de estar desconectados | [Repositório próprio](https://github.com/Nicoli-Kassa/GS_CitizenTech_IA-ML_MeConta) | ✅ Pronta (fora desta API) |

---

## C# Software Development

**A parte dela no Me Conta:** toda a Web API em C# / .NET 10. É onde ficam as regras que fazem o Me Conta funcionar: só a família vê a família, o WhatsApp não se repete, a pergunta da semana nunca repete, o filtro anti-golpe, a resposta que vira página do caderno.

| Critério | Onde é atendido |
| --- | --- |
| **Programação orientada a objetos** | Abstração: [`IPergunta`](../src/MeConta.Domain/Entidades/IPergunta.cs), [`Pergunta`](../src/MeConta.Domain/Entidades/Pergunta.cs) e [`ArquivoDeMidia`](../src/MeConta.Domain/ValueObjects/ArquivoDeMidia.cs) abstratas. Herança: [`Entidade`](../src/MeConta.Domain/Comum/Entidade.cs) → todas as entidades; `Pergunta` → [`PerguntaCatalogo`](../src/MeConta.Domain/Entidades/PerguntaCatalogo.cs) / [`PerguntaDaFamilia`](../src/MeConta.Domain/Entidades/PerguntaDaFamilia.cs); `ArquivoDeMidia` → [`ArquivoDeAudio`](../src/MeConta.Domain/ValueObjects/ArquivoDeAudio.cs) / [`ArquivoDeFoto`](../src/MeConta.Domain/ValueObjects/ArquivoDeFoto.cs). Polimorfismo: `VisivelPara(familiaId)` e o template method dos arquivos. Encapsulamento: setters privados e coleções somente leitura em [`Familia`](../src/MeConta.Domain/Entidades/Familia.cs) e [`EnvioPergunta`](../src/MeConta.Domain/Entidades/EnvioPergunta.cs). Value objects: [`Telefone`](../src/MeConta.Domain/ValueObjects/Telefone.cs), [`Semana`](../src/MeConta.Domain/ValueObjects/Semana.cs). Detalhes no README, seção [Modelo de domínio e POO](../README.md#modelo-de-domínio-e-poo). |
| **Web API** | 10 controllers em [`src/MeConta.Api/Controllers`](../src/MeConta.Api/Controllers), todos em `/api/v1`, com códigos HTTP corretos (201, 204, 400, 401, 403, 404, 409, 413). Login com ASP.NET Identity e token Bearer ([`Program.cs`](../src/MeConta.Api/Program.cs)). Erros no padrão ProblemDetails ([`TratadorDeExcecoes`](../src/MeConta.Api/Configuracao/TratadorDeExcecoes.cs)). Tabela completa no README, seção [Endpoints](../README.md#endpoints). |
| **EF Core + LINQ** | [`AppDbContext`](../src/MeConta.Infrastructure/Persistencia/AppDbContext.cs) com Fluent API em [`Configuracoes/`](../src/MeConta.Infrastructure/Persistencia/Configuracoes), herança TPH nas perguntas e conversores de valor. LINQ em sintaxe de consulta (`from ... join ... select`) e de métodos (`Where`, `Include`, `Skip/Take`, `SumAsync`) em [`Repositorios.cs`](../src/MeConta.Infrastructure/Repositorios/Repositorios.cs). |
| **async/await** | Todo o acesso ao banco e aos arquivos é assíncrono, com `CancellationToken` do controller até o EF Core: controllers → [serviços](../src/MeConta.Application/Servicos) → [repositórios](../src/MeConta.Infrastructure/Repositorios) → [armazenamento em disco](../src/MeConta.Infrastructure/Adapters/ArmazenamentoEmDiscoAdapter.cs). |
| **Qualidade do código** | Arquitetura em 4 projetos com a regra de dependência garantida pelo compilador ([`MeConta.slnx`](../MeConta.slnx)); interfaces e injeção de dependência ([`InjecaoDeDependencia.cs`](../src/MeConta.Infrastructure/InjecaoDeDependencia.cs), [`RegistroDaAplicacao.cs`](../src/MeConta.Api/Configuracao/RegistroDaAplicacao.cs)); `nullable` ligado e avisos tratados ([`Directory.Build.props`](../Directory.Build.props)); classes `sealed`, comentários XML; relógio injetável (`TimeProvider`) para testar datas; 354 testes. |
| **README, Swagger/Scalar, evidências** | [README](../README.md) com Ficha, como executar e integrantes; `/swagger` e `/scalar`; prints em [`docs/evidencias`](evidencias). |

## SOA e Web Services

**A parte dela no Me Conta:** os serviços que o app mobile e o porta-retrato consomem. A API expõe contratos REST versionados (`/api/v1`), documentados em OpenAPI, guarda tudo no SQL Server e é a mesma para todos os clientes.

| Critério | Onde é atendido |
| --- | --- |
| **Domínio** | Projeto [`MeConta.Domain`](../src/MeConta.Domain), sem nenhum pacote externo: entidades, value objects, regras ([`FiltroAntiGolpe`](../src/MeConta.Domain/Regras/FiltroAntiGolpe.cs), [`SugestaoSemanal`](../src/MeConta.Domain/Regras/SugestaoSemanal.cs), [`FilaDoPortaRetrato`](../src/MeConta.Domain/Regras/FilaDoPortaRetrato.cs)) e exceções de negócio que viram 400, 409 e 413. Casos de uso em [`MeConta.Application/Servicos`](../src/MeConta.Application/Servicos), com DTOs em [`Dtos/`](../src/MeConta.Application/Dtos) para não expor as entidades. Tabela de regras no README, seção [Regras de negócio](../README.md#regras-de-negócio). |
| **Banco de dados** | SQL Server com EF Core 10 (LocalDB no desenvolvimento), 11 tabelas do Me Conta mais as do Identity, índices únicos (WhatsApp na família, chave de idempotência, código do porta-retrato). Diagrama no README, seção [Banco de dados e migrações](../README.md#banco-de-dados-e-migrações). Print: [`10-banco.png`](evidencias/10-banco.png). |
| **Migrações** | [`InitialCreate`](../src/MeConta.Infrastructure/Persistencia/Migrations/20261112234120_InitialCreate.cs) (modelo e catálogo de 25 perguntas via `HasData`) [`PortaRetrato`](../src/MeConta.Infrastructure/Persistencia/Migrations/20261115195031_PortaRetrato.cs) e `Privacidade` (incrementais, na mesma [pasta](../src/MeConta.Infrastructure/Persistencia/Migrations)), aplicadas ao subir a API ([`DbInicializador`](../src/MeConta.Infrastructure/Persistencia/DbInicializador.cs)). Print: [`11-migracoes.png`](evidencias/11-migracoes.png). |
| **Documentação automática** | OpenAPI em `/openapi/v1.json`, exibido no Swagger UI (`/swagger`) e no Scalar (`/scalar`), com título, descrição e esquema Bearer ([`DocumentacaoOpenApi`](../src/MeConta.Api/Configuracao/DocumentacaoOpenApi.cs)). Prints: [`01-swagger.png`](evidencias/01-swagger.png), [`02-scalar.png`](evidencias/02-scalar.png). |
| **Testes automatizados** | 354 testes xUnit em [`tests/MeConta.UnitTests`](../tests/MeConta.UnitTests): domínio, regras, serviços, motor de dados pessoais e IA na remediação, com dublês escritos à mão. Print: [`12-testes.png`](evidencias/12-testes.png). Além deles, o [roteiro de testes](ROTEIRO_DE_TESTES.md) e o arquivo [`MeConta.Api.http`](../src/MeConta.Api/MeConta.Api.http) cobrem os 117 passos do roteiro. |
| **GitHub, README, evidências** | Este repositório; [README](../README.md) com execução e integrantes; prints em [`docs/evidencias`](evidencias). |

## Physical Computing (IoT)

**A parte dela no Me Conta:** o porta-retrato Me Conta, para o idoso que ainda não usa bem o celular (degrau "Conectar", US15). Um anel de LEDs acende quando a família manda uma pergunta, a telinha mostra quem perguntou e o botão grande "quero contar" avisa a família no app. Um sensor de luz deixa o brilho mais baixo e tira o som quando a sala está escura. Documentação completa em **[iot/README.md](../iot/README.md)**.

```
App ──HTTP──> Me Conta API <──HTTP── Node-RED <──MQTT──> test.mosquitto.org <──MQTT──> ESP32 (Wokwi)
```

| Entregável | Onde está |
| --- | --- |
| **Link do projeto no Wokwi** | [wokwi.com/projects/480807903168932865](https://wokwi.com/projects/480807903168932865) |
| **Link do vídeo (até 4 min)** | [Assistir no YouTube](https://youtu.be/INSERIR-LINK-DO-VIDEO-IOT) |
| **Arquivo com os integrantes** | [`iot/integrantes.txt`](../iot/integrantes.txt) |

| O que é pedido | Onde é atendido |
| --- | --- |
| **Circuito integrado à solução, sem projeto paralelo** | O aparelho usa os mesmos dados da família: pareamento ao idoso ([`PortaRetratoController`](../src/MeConta.Api/Controllers/PortaRetratoController.cs)), rotas do aparelho com chave própria ([`AparelhoPortaRetratoController`](../src/MeConta.Api/Controllers/AparelhoPortaRetratoController.cs): `estado`, `quero-contar`, `conexao`) e avisos que a família vê no app ([`AvisosController`](../src/MeConta.Api/Controllers/AvisosController.cs)). |
| **Regras do aparelho** | [`PortaRetrato`](../src/MeConta.Domain/Entidades/PortaRetrato.cs), [`AvisoQueroContar`](../src/MeConta.Domain/Entidades/AvisoQueroContar.cs), [`FilaDoPortaRetrato`](../src/MeConta.Domain/Regras/FilaDoPortaRetrato.cs) e [`AparelhoPortaRetratoService`](../src/MeConta.Application/Servicos/AparelhoPortaRetratoService.cs): só o hash da chave é guardado, "quero contar" não duplica, conectado = sinal de vida nos últimos 90 s. |
| **Banco** | Migração [`PortaRetrato`](../src/MeConta.Infrastructure/Persistencia/Migrations/20261115195031_PortaRetrato.cs) (tabelas `PortaRetratos` e `AvisosQueroContar`) e porta-retrato de demonstração da Vó Lourdes (código `k7m2q9xd`). |
| **Testes e evidências** | [`PortaRetratoTests`](../tests/MeConta.UnitTests/Domain/PortaRetratoTests.cs), [`FilaDoPortaRetratoTests`](../tests/MeConta.UnitTests/Regras/FilaDoPortaRetratoTests.cs), [`AparelhoPortaRetratoServiceTests`](../tests/MeConta.UnitTests/Servicos/AparelhoPortaRetratoServiceTests.cs), [`PortaRetratoServiceTests`](../tests/MeConta.UnitTests/Servicos/PortaRetratoServiceTests.cs); chamadas 67 a 88 do [`MeConta.Api.http`](../src/MeConta.Api/MeConta.Api.http) (Bloco K do [roteiro](ROTEIRO_DE_TESTES.md)); prints [13](evidencias/13-porta-retrato-estado.png) a [17](evidencias/17-porta-retrato-moldura-apagada.png). |
| **Circuito com ESP32, sensores e componentes** | [`iot/wokwi/`](../iot/wokwi): [`diagram.json`](../iot/wokwi/diagram.json) com ESP32 DevKit C v4, anel de 24 LEDs RGB (moldura), tela OLED SSD1306, botão "quero contar", buzzer, sensor de luz (LDR) e chave para simular a queda do Wi-Fi; firmware comentado em [`sketch.ino`](../iot/wokwi/sketch.ino). Tabela de pinos em [O circuito](../iot/README.md#o-circuito). |
| **Integração com a solução** | Ponte [`iot/node-red/flows.json`](../iot/node-red/flows.json): MQTT ↔ rotas da API (`estado`, `quero-contar`, `conexao`, `avisos`) e painel `/ui` com a visão da família. Mensagens em [Mensagens MQTT](../iot/README.md#mensagens-mqtt). |
| **Funcionamento demonstrado** | Casos CT36 (pergunta acende a moldura e o botão avisa a família) e CT37 (sem Wi-Fi) aprovados em 16/11; prints da caixinha e do painel em [`iot/evidencias`](../iot/evidencias) e na seção [Evidências](../iot/README.md#evidências). |

## Cybersecurity

**A parte dela no Me Conta:** proteger o idoso antes de uma memória sair da família e ir para o mapa do bairro (degrau "Expandir", US18). Um motor de regras procura dados pessoais (CPF, saúde, senhas, endereço, rotina da casa), o taint analysis garante que texto não verificado não chega a saídas inseguras, e um LLM (Gemini) traduz cada risco em linguagem simples, para a família e para o painel executivo "Risco Cidadão". Visão geral, Ficha e evidências: [`docs/cyber/README.md`](cyber/README.md).

| O que é pedido | Onde é atendido |
| --- | --- |
| **Mapeamento de PII (motor de regras)** | Pronto: projeto [`src/MeConta.Privacidade`](../src/MeConta.Privacidade) com 17 regras em [`regras-pii.json`](../src/MeConta.Privacidade/Regras/regras-pii.json), validadores de CPF, cartão e telefone, normalização de texto falado e índice Risco Cidadão; [testes](../tests/MeConta.UnitTests/Privacidade) com dois conjuntos de memórias simuladas; [como funciona e avaliação](cyber/motor-pii.md). Ligado às rotas [`/paginas/{id}/analise-privacidade` e `/publicacao`](../src/MeConta.Api/Controllers/MapaDoBairroController.cs) pelo [`PrivacidadeService`](../src/MeConta.Application/Servicos/PrivacidadeService.cs); passos 89 a 108 do [roteiro](ROTEIRO_DE_TESTES.md). |
| **Taint analysis** | Pronto, em três camadas ([como funciona e auditoria](cyber/taint-analysis.md)): tipos que separam texto do usuário de texto verificado ([`TextosRastreados.cs`](../src/MeConta.Privacidade/Taint/TextosRastreados.cs)); 5 regras Semgrep em modo taint + 2 de segredos em [`seguranca/semgrep/`](../seguranca/semgrep), com casos de teste; pipeline no [GitHub Actions](../.github/workflows/seguranca.yml) com Semgrep, TruffleHog e testes. A auditoria do protótipo achou 5 vazamentos reais (texto da família indo cru para o broker MQTT do porta-retrato e caminho da URL no log de erro), corrigidos: [antes](../seguranca/relatorios/antes-semgrep.txt) e [depois](../seguranca/relatorios/depois-semgrep.txt). Log de auditoria só com dados mascarados ([`AuditoriaEmLog`](../src/MeConta.Api/Adapters/AuditoriaEmLog.cs)). |
| **Tradução via IA** | Pronto ([como funciona](cyber/remediacao-ia.md)): o [`TradutorDeRisco`](../src/MeConta.Application/Servicos/TradutorDeRisco.cs) manda ao Gemini ([`ExplicadorGemini`](../src/MeConta.Infrastructure/Ia/ExplicadorGemini.cs)) só o tipo do dado, o trecho mascarado e o texto com "[CPF removido]"; confere o pedido com o motor antes de sair e cada frase da resposta depois; frase com dado pessoal é trocada pelas [explicações locais](../src/MeConta.Application/Servicos/ExplicacoesLocais.cs), que também valem sem chave ou sem cota. Instruções separadas dos dados contra injeção de instruções. Rotas [`/paginas/{id}/explicacao-de-risco`](../src/MeConta.Api/Controllers/MapaDoBairroController.cs) (família: alerta, risco real, o que fazer e a memória reescrita sem os dados) e [`/risco-cidadao/auditoria`](../src/MeConta.Api/Controllers/RiscoCidadaoController.cs) (as 5 falhas do Semgrep traduzidas); [40 testes](../tests/MeConta.UnitTests/Remediacao); passos 109 a 114 e 117 do [roteiro](ROTEIRO_DE_TESTES.md). |
| **Dashboard "Risco Cidadão"** | Pronto: painel executivo em `http://localhost:5080/risco-cidadao/` ([`wwwroot/risco-cidadao`](../src/MeConta.Api/wwwroot/risco-cidadao)), atualizado a cada 5 segundos, com o índice, vazamentos evitados, gráficos por dia, por tipo e por bairro (cada um com tabela), os alertas traduzidos pela IA ([`/risco-cidadao/alertas`](../src/MeConta.Api/Controllers/RiscoCidadaoController.cs)) e a auditoria do código. Dados do [`RiscoCidadaoService`](../src/MeConta.Application/Servicos/RiscoCidadaoService.cs), só agregados e mascarados; página com `Content-Security-Policy` e limite de pedidos por IP. Atividade simulada para o vídeo: [`simular-atividade.ps1`](../seguranca/demo/simular-atividade.ps1); passos 115 e 116 do [roteiro](ROTEIRO_DE_TESTES.md). |
| **Proteções que a API já tem** | Dados mínimos do idoso (sem CPF, endereço ou saúde, [`IdosoDtos`](../src/MeConta.Application/Dtos/IdosoDtos.cs)); [`FiltroAntiGolpe`](../src/MeConta.Domain/Regras/FiltroAntiGolpe.cs) contra pedidos de PIX, senha e código; acesso só da família ([`ControleDeAcesso`](../src/MeConta.Application/Servicos/ControleDeAcesso.cs)); chave do porta-retrato sorteada com gerador criptográfico ([`GeradorDeCredenciais`](../src/MeConta.Infrastructure/Adapters/GeradorDeCredenciais.cs)) e guardada só como hash SHA-256 ([`PortaRetrato`](../src/MeConta.Domain/Entidades/PortaRetrato.cs)); erros sem detalhe interno ([`TratadorDeExcecoes`](../src/MeConta.Api/Configuracao/TratadorDeExcecoes.cs)); nome de arquivo nunca vira caminho ([`ArmazenamentoEmDiscoAdapter`](../src/MeConta.Infrastructure/Adapters/ArmazenamentoEmDiscoAdapter.cs)); dependência vulnerável `System.Security.Cryptography.Pkcs` atualizada para 10.0.13 ([`MeConta.Infrastructure.csproj`](../src/MeConta.Infrastructure/MeConta.Infrastructure.csproj)). |

## Operating Systems

**A parte dela no Me Conta:** o servidor Linux onde a API roda, montado do zero por script Bash numa VM do Azure, que se recupera sozinho de falhas, avisa antes de CPU, memória ou disco acabarem e registra quem mexeu em quê. Documentação completa em **[linux/README.md](../linux/README.md)**.

| O que é pedido | Onde é atendido |
| --- | --- |
| **Infraestrutura: rede, DNS, IP, hostname** | [`linux/etapas/rede.sh`](../linux/etapas/rede.sh): hostname, `/etc/hosts` com domínio interno, IP privado fixo no netplan com rollback automático, DNS no systemd-resolved; [`sistema.sh`](../linux/etapas/sistema.sh) e [`seguranca.sh`](../linux/etapas/seguranca.sh): fuso, swap, SSH só com chave, firewall `ufw`. |
| **Provisionamento da aplicação web** | [`linux/etapas/aplicacao.sh`](../linux/etapas/aplicacao.sh): build da API a partir deste repositório, uma pasta por versão com volta automática se o `/health` falhar, serviço systemd isolado ([`meconta-api.service`](../linux/arquivos/meconta-api.service)), SQLite e nginx na porta 80 ([`nginx-meconta.conf`](../linux/arquivos/nginx-meconta.conf)). |
| **Monitoramento de CPU, disco e memória com alertas** | [`linux/monitor/meconta-monitor.sh`](../linux/monitor/meconta-monitor.sh): alerta acima de 80% (log, journal, terminal e webhook opcional) e painel web em `/servidor/`. |
| **Monitoramento como serviço tolerante a falhas** | [`meconta-monitor.service`](../linux/arquivos/meconta-monitor.service): `Restart=always`, watchdog de 60 s, protegido do OOM; o monitor também reinicia a API quando o `/health` desta API falha 3 vezes. |
| **Logs de auditoria** | [`linux/etapas/auditoria.sh`](../linux/etapas/auditoria.sh) e [`auditd-meconta.rules`](../linux/arquivos/auditd-meconta.rules): auditd, log do provisionamento, log de acesso do nginx, journal persistente; relatório em [`ferramentas/auditoria.sh`](../linux/ferramentas/auditoria.sh). Na API, erros inesperados são registrados sem o caminho pedido ([`TratadorDeExcecoes`](../src/MeConta.Api/Configuracao/TratadorDeExcecoes.cs)). |
| **Teste de falha** | [`linux/ferramentas/teste-de-falha.sh`](../linux/ferramentas/teste-de-falha.sh): derruba e congela a API e o monitor, estressa CPU, memória e disco e confere a recuperação. |
| **O que esta API oferece ao servidor** | `GET /health` (API e banco), configuração toda por variável de ambiente (`Banco__Provedor=Sqlite` no servidor), IP real do cliente atrás do nginx (`X-Forwarded-For`, para o limite de requisições) e leitura de segredos cifrados pelo systemd (`$CREDENTIALS_DIRECTORY`), em [`Program.cs`](../src/MeConta.Api/Program.cs). |

## Testing, Compliance & QA

**A parte dela no Me Conta:** garantir que o que foi combinado é o que foi feito. O backlog (3 épicos, 11 features, 18 user stories) e os 43 casos de teste estão no [Azure DevOps](https://dev.azure.com/GSCitizenTech/MeConta).

| O que é pedido | Ligação com esta API |
| --- | --- |
| **Features com descrição e critérios de aceite** | Cada critério de aceite virou uma regra no domínio, com a mesma mensagem de erro (README, seção [Regras de negócio](../README.md#regras-de-negócio)). A coluna "User story" da tabela de [Endpoints](../README.md#endpoints) liga cada rota à US do backlog. |
| **Casos de teste positivos e negativos** | Os casos que rodam na API (por exemplo CT04, CT25 e CT29, pelo Swagger) seguem o [roteiro de testes](ROTEIRO_DE_TESTES.md); os limites dos casos (60 e 61 caracteres, 20 MB, convite de 48 h) também estão nos testes automatizados. |
| **Compliance** | LGPD (dados mínimos, só a família vê, quem criou apaga) no README, seção [Privacidade e segurança](../README.md#privacidade-e-segurança). |

## Mobile

**A parte dela no Me Conta:** o app que a neta usa. O caderno da família é a primeira tela; a partir dele, ela pergunta, envia pelo WhatsApp e guarda a resposta.

| O que é pedido | Ligação com esta API |
| --- | --- |
| **Consumo de dados** | O app consome estas rotas (login, famílias, perguntas, envios, caderno, avisos) e usa um mock com as mesmas regras e mensagens quando a API não está configurada. |
| **Rodar no celular** | Perfil `rede-local` ([`launchSettings.json`](../src/MeConta.Api/Properties/launchSettings.json)) e CORS liberado ([`Program.cs`](../src/MeConta.Api/Program.cs)). |
| **Modo offline** | A API aceita a `ChaveIdempotencia` da página: o que o app guardou sem internet não duplica ao sincronizar ([`CadernoService`](../src/MeConta.Application/Servicos/CadernoService.cs)). |

## IA & ML

**A parte dela no Me Conta:** responder com dados reais da PNAD Contínua TIC 2025 quais idosos têm mais chance de estar desconectados, ou seja, onde o degrau "Conectar" é mais necessário. Não faz parte desta API; está no [repositório de IA & ML](https://github.com/Nicoli-Kassa/GS_CitizenTech_IA-ML_MeConta). Os números que ela gerou (9,1 milhões de idosos sem internet; 4,9 milhões moram com alguém que usa) aparecem no README, seção [O problema](../README.md#o-problema).
