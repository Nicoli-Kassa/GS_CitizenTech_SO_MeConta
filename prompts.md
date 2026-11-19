# Registro de uso de IA

Este arquivo registra como usei inteligência artificial como ferramenta de apoio no backend do Me Conta, como pede o brief da Global Solution.

Defini o escopo, a arquitetura, as tecnologias e as regras de negócio a partir do backlog do projeto. Usei a IA como apoio para tirar dúvidas, acelerar a escrita de código e documentação e resolver problemas. Todo o conteúdo gerado com apoio da IA foi revisado, ajustado, compilado e testado por mim.

**Ferramenta:** Claude (Anthropic)
**Período:** 10 a 19/11/2026

---

## Resumo

| Etapa                    | Data          | Meu trabalho                                                                 | Apoio da IA                                                              |
| ------------------------ | ------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 1. Planejamento          | 10/11         | Defini a arquitetura, o banco, o login, o escopo e quais user stories entram | Sugestões de organização do domínio e dos endpoints                      |
| 2. Domínio e testes      | 10/11         | Defini as regras a partir dos critérios de aceite, revisei e rodei os testes | Geração da primeira versão das classes e dos testes                      |
| 3. Banco, serviços e API | 12/11         | Gerei a migração, subi a API, testei os endpoints e conferi o banco          | Geração da primeira versão das camadas Application, Infrastructure e Api |
| 4. Documentação          | 12/11 e 14/11 | Revisei os textos, preenchi os dados, segui o roteiro e tirei os prints      | Estrutura do README e do roteiro de testes                               |
| 5. Problemas             | 14/11         | Investiguei os erros e apliquei as correções                                 | Explicação das causas                                                    |
| 6. Porta-retrato (IoT)   | 15/11         | Defini o papel do aparelho, gerei a migração, testei as rotas e tirei os prints | Primeira versão das entidades, serviços, rotas, testes e roteiro         |
| 7. Dependência vulnerável | 15/11        | Atualizei o pacote e confirmei o build sem avisos                            | Explicação do aviso e da versão corrigida                                |
| 8. Motor de PII, filtro na API, taint analysis, IA na remediação e painel (Cybersecurity) | 15 a 18/11 | Defini o que conta como dado de risco, o que bloqueia, as regras de consentimento, as saídas inseguras e o que a IA pode receber; gerei a migração e a chave do Gemini, rodei os testes, o roteiro e o pipeline | Primeira versão do módulo, das regras (PII e Semgrep), das rotas do mapa do bairro, da integração com o Gemini, do painel, dos testes, do pipeline e dos conjuntos de memórias simuladas |
| 9. Circuito no Wokwi     | 16/11         | Escolhi os componentes e o visual da caixinha, montei no Wokwi e testei cada situação | Primeira versão do firmware e do `diagram.json`                    |
| 10. Ponte Node-RED e painel | 16/11      | Instalei e configurei o Node-RED, rodei o ciclo completo com a API e ajustei o visual do painel | Primeira versão do fluxo e do painel                       |
| 11. Documentação do IoT  | 16/11         | Revisei os textos e tirei os prints                                          | Estrutura do README da pasta `iot/`                                      |
| 12. Servidor Linux (Operating Systems) | 16 a 19/11 | Criei a VM no Azure, escolhi o banco e as regras de rede, rodei o provisionamento e o teste de falha e tirei os prints | Primeira versão dos scripts Bash, das units systemd, do monitor, das regras de auditoria e do README da pasta `linux/` |

---

## 1. Planejamento do backend · 10/11/2026

**O que eu precisava:** organizar uma Web API que atendesse às disciplinas C# Software Development e SOA e Web Services, a partir do backlog do Me Conta (US01 a US18).

**Como usei a IA:** enviei o brief, a Ficha da CitizenTech, o backlog e os critérios de avaliação, e pedi sugestões de entidades, estrutura de pastas e endpoints.

**Minhas decisões:**

- Uma única API para as duas disciplinas, num só repositório, organizada em quatro camadas (Domain, Application, Infrastructure, Api).
- SQL Server como banco, com LocalDB no desenvolvimento.
- ASP.NET Identity para o login, com token Bearer.
- xUnit nos testes, com dublês escritos à mão.
- Documentação automática em Swagger UI e Scalar.
- Mapa do bairro (US16, US17) e filtro de dados pessoais (US18) fora desta entrega, por prazo.

---

## 2. Domínio e testes unitários · 10/11/2026

**O que eu precisava:** transformar os critérios de aceite do backlog em regras do domínio, com testes.

**Como usei a IA:** pedi apoio para gerar a primeira versão das entidades, value objects, regras e testes unitários, seguindo as regras e as mensagens de erro do backlog.

**Resultado:**

- Entidades `Familia`, `Membro`, `Participacao`, `Convite`, `Idoso`, `Categoria`, `Pergunta` (abstrata) com `PerguntaCatalogo` e `PerguntaDaFamilia`, `EnvioPergunta` e `PaginaCaderno`.
- Value objects `Telefone`, `Semana` e `ArquivoDeMidia` (abstrato), com `ArquivoDeAudio` e `ArquivoDeFoto`.
- Regras com interface: `FiltroAntiGolpe` e `SugestaoSemanal`.
- Testes unitários dos critérios de aceite das US01 a US08, US11 e US14.

**Meu trabalho de validação:**

- Rodei `dotnet build` e `dotnet test`: 103 testes aprovados, nenhuma falha.
- Conferi se as mensagens de erro batiam com o backlog (ex.: "Dê um nome para a família", "Esse número já está na família").
- Estudei onde cada pilar de POO aparece no código: herança em `Pergunta` e `ArquivoDeMidia`, polimorfismo em `VisivelPara`, encapsulamento nos setters privados e nas coleções somente leitura.

---

## 3. Banco de dados, serviços e API · 12/11/2026

**O que eu precisava:** ligar o domínio ao banco SQL Server e expor os casos de uso como API REST documentada.

**Como usei a IA:** pedi apoio para gerar a primeira versão das camadas de aplicação, infraestrutura e API, seguindo a arquitetura definida na etapa 1.

**Resultado:**

- **Application:** serviços com interfaces (`FamiliaService`, `IdosoService`, `PerguntaService`, `EnvioService`, `CadernoService`, `IndicadorService`, `ControleDeAcesso`), DTOs e contratos de repositório e de adapters.
- **Infrastructure:** `AppDbContext` com Identity e configurações Fluent API (herança TPH, relação N:N, índices únicos). Também o catálogo de perguntas via `HasData`, os repositórios, as consultas LINQ e o armazenamento de arquivos.
- **Api:** controllers, login com `MapIdentityApi`, erros no formato ProblemDetails, OpenAPI com Swagger UI e Scalar, e a rota `/health`.

**Meu trabalho de validação:**

- Gerei a migração inicial com `dotnet ef migrations add InitialCreate` e subi a API, que criou o banco e aplicou a migração.
- Testei os endpoints pelo Swagger com a conta de demonstração, incluindo os casos de erro (400, 403, 404, 409).
- Conferi no banco as tabelas criadas e o catálogo de perguntas.

---

## 4. Documentação e roteiro de testes · 12/11 e 14/11/2026

**O que eu precisava:** documentar a solução e organizar os testes manuais e as evidências.

**Como usei a IA:** pedi apoio para estruturar o README (a partir da minha Ficha da CitizenTech e do backlog), um roteiro com todas as requisições e o arquivo `.http` para testar no Visual Studio.

**Meu trabalho:**

- Revisei os textos do `README.md`, preenchi meu RM e os links do repositório e do pitch.
- Segui o `docs/ROTEIRO_DE_TESTES.md` requisição por requisição e tirei os prints de `docs/evidencias/`.
- Usei somente dados fictícios nos testes (e-mails `@example.com` e telefones inventados).

---

## 5. Problemas resolvidos · 14/11/2026

| Problema                                            | Como a IA ajudou                                                                         | O que eu fiz                                                                   |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Swagger devolvia **401** depois do login            | Explicou que o token estava sendo enviado com aspas (`Bearer "CfDJ8..."`)                | Corrigi o token no **Authorize**, sem aspas, e a chamada passou a devolver 200 |
| Ver o banco e as migrações sem o Visual Studio      | Indicou a extensão MSSQL do VS Code e os comandos `dotnet ef migrations list` e `script` | Instalei a extensão e conectei ao banco                                        |
| Erro de conexão no VS Code ("server was not found") | Apontou que o nome do servidor estava no campo errado                                    | Corrigi para `(localdb)\MSSQLLocalDB` e conectei ao banco `MeConta`            |
| Revisão final da entrega                            | Sugeriu uma lista de checagem dos critérios de C# e SOA                                  | Usei a lista para revisar a entrega antes de enviar                            |

---

## 6. Porta-retrato Me Conta (IoT) · 15/11/2026

**O que eu precisava:** ligar à API o porta-retrato da solução (US15), uma caixinha com ESP32 que acende quando chega pergunta e tem um botão "quero contar", conversando com a API por meio de uma ponte Node-RED.

**Como usei a IA:** expliquei como o aparelho funciona e pedi apoio para gerar a primeira versão das entidades, dos serviços, das rotas, dos testes e da atualização do roteiro de testes.

**Minhas decisões:**

- O aparelho não usa o login da família: ele se identifica por uma chave própria, enviada no cabeçalho `X-Chave-PortaRetrato`, e a API guarda só o hash dela.
- A chave só dá acesso ao estado do próprio idoso e ao botão "quero contar". Para o aparelho vai só o apelido, o primeiro nome de quem perguntou e o texto da pergunta.
- O aviso "quero contar" fica ligado ao idoso, e a família vê os avisos no app.

**Resultado:**

- Entidades `PortaRetrato` e `AvisoQueroContar`, a regra `FilaDoPortaRetrato` e os serviços `PortaRetratoService`, `AparelhoPortaRetratoService` e `AvisoService`.
- Rotas `/api/v1/porta-retrato/estado`, `/quero-contar` e `/conexao` para o aparelho, e as rotas de pareamento e de avisos para a família.
- Testes unitários dos serviços com repositórios em memória: o total passou de 103 para 151.
- Bloco K do roteiro de testes (passos 67 a 88) e o arquivo `.http` com todas as chamadas.

**Meu trabalho de validação:**

- Gerei a migração com `dotnet ef migrations add PortaRetrato` e rodei `dotnet build` e `dotnet test`: 151 testes aprovados.
- Testei as rotas pelo Swagger: moldura acesa, "quero contar", moldura apagada, chave inválida (401) e avisos para a família, e tirei os prints de `docs/evidencias/`.

---

## 7. Dependência vulnerável · 15/11/2026

| Problema | Como a IA ajudou | O que eu fiz |
| --- | --- | --- |
| O build mostrava os avisos NU1902 e NU1903 no pacote `System.Security.Cryptography.Pkcs` 9.0.11, usado indiretamente pelo projeto | Explicou que a versão tinha falhas de negação de serviço publicadas e qual versão já trazia a correção | Adicionei `System.Security.Cryptography.Pkcs` 10.0.13 na Infrastructure e confirmei o build sem avisos |

---

## 8. Motor de dados pessoais (Cybersecurity) · 15/11/2026

**O que eu precisava:** um motor que procure dados pessoais numa memória antes de ela sair do caderno da família e ir para o mapa do bairro (US18), com regras que possam ser acrescentadas sem mexer no código e um índice "Risco Cidadão" para o painel.

**Como usei a IA:** expliquei o problema, os dados que preocupam (CPF, saúde, senhas e o que expõe a rotina de uma pessoa idosa) e o fato de as respostas chegarem em áudio. Pedi apoio para gerar a primeira versão do módulo, das regras, dos testes e de dois conjuntos de memórias simuladas para medir os acertos.

**Minhas decisões:**

- O módulo fica dentro da solução da API (`src/MeConta.Privacidade`), sem pacote externo, para rodar onde o dado entra.
- As regras ficam num arquivo JSON: dado novo = regra nova no arquivo.
- Três níveis: risco alto bloqueia a publicação (CPF, RG, cartão, dados bancários, PIX, senha, código de verificação); risco médio pede confirmação da família (saúde, telefone, e-mail, endereço, CEP, data de nascimento, rotina da casa).
- Na dúvida, bloquear: texto grande demais ou análise que passa do tempo não é liberado.
- O resultado nunca guarda o dado em claro, só o trecho mascarado.
- A avaliação mostra também os erros da primeira rodada no conjunto de validação, e não só o resultado depois dos ajustes.

**Resultado:**

- Projeto `MeConta.Privacidade`: normalização (acentos, caracteres invisíveis, números falados), 17 regras em `regras-pii.json`, validadores de CPF, cartão e telefone, combinações de risco, índice Risco Cidadão e os tipos `TextoDoUsuario` e `TextoVerificado`.
- 117 testes novos em `tests/MeConta.UnitTests/Privacidade`, incluindo os casos CT41 a CT43 do backlog.
- Conjuntos de 64 e 30 memórias simuladas com gabarito, e a ferramenta `tools/MeConta.Privacidade.Avaliacao`, que gera a tabela de precisão e recall.
- Documentação em `docs/cyber/motor-pii.md`.

**Meu trabalho de validação:**

- Rodei `dotnet build` e `dotnet test`: 268 testes aprovados.
- Rodei a ferramenta de avaliação e conferi as tabelas do `docs/cyber/motor-pii.md`.
- Testei frases do dia a dia que não podem gerar alerta, como "panela de pressão" e "me conta 1950".

### Parte 2 · Filtro ligado à API e mapa do bairro · 16/11/2026

**O que eu precisava:** usar o motor de verdade na API: guardar a transcrição do áudio, conferir título e transcrição antes de levar uma memória ao mapa do bairro (US16, US17, US18) e calcular o indicador "Risco Cidadão" a partir do que aconteceu.

**Como usei a IA:** descrevi o fluxo da publicação e as regras de consentimento e pedi apoio para gerar a primeira versão das entidades, dos serviços, das rotas, dos testes e do bloco L do roteiro.

**Minhas decisões:**

- Nada vai para o mapa sem a autorização da pessoa idosa, registrada na memória publicada.
- Título, transcrição e bairro passam pelo motor; o que vai para o mapa é o texto liberado por ele.
- Dado de risco alto bloqueia sempre; dado de risco médio só vai com a confirmação da família.
- A tentativa barrada também fica no histórico, só com o tipo do dado e o trecho mascarado, para o painel mostrar os vazamentos evitados.
- O mapa do bairro e o painel "Risco Cidadão" são abertos (sem login), mas mostram só apelido, título, texto liberado, números e trechos mascarados.
- As páginas de demonstração do filtro ficam desligadas por padrão, para não mudar os números do roteiro dos blocos anteriores.

**Resultado:**

- Entidades `MemoriaDoBairro` e `RegistroDePrivacidade`, transcrição na página, serviços `PrivacidadeService` e `RiscoCidadaoService`.
- Rotas `/paginas/{id}/transcricao`, `/paginas/{id}/analise-privacidade`, `/paginas/{id}/publicacao`, `/bairros/{bairro}/memorias`, `/memorias/{id}/audio` e `/risco-cidadao`; publicação recusada responde 422 com a análise mascarada.
- 42 testes novos (310 no total) e o bloco L do roteiro (passos 89 a 108).

**Meu trabalho de validação:**

- Gerei a migração com `dotnet ef migrations add Privacidade` e rodei `dotnet build` e `dotnet test`: 310 testes aprovados.
- Segui o bloco L do roteiro pelo Swagger e tirei os prints 18 a 21.

### Parte 3 · Taint analysis e pipeline de segurança · 16/11/2026

**O que eu precisava:** provar que texto escrito pela família não chega a uma saída insegura (log, porta-retrato, IA, mapa do bairro) sem passar pelo motor, e que isso é conferido automaticamente a cada mudança.

**Como usei a IA:** pedi apoio para escrever as regras do Semgrep em modo taint, os casos de teste das regras, o pipeline do GitHub Actions e a configuração de pre-commit, e para rodar a auditoria no código que já estava no GitHub.

**Minhas decisões:**

- As regras do Me Conta bloqueiam o pipeline; as regras públicas de C# entram só como relatório.
- Tratar o porta-retrato como saída pública, porque a pergunta passa por um broker MQTT aberto.
- Corrigir os vazamentos que a auditoria achou, em vez de marcar como exceção.
- Registrar uma linha de auditoria a cada verificação, só com ids, resultado e trechos mascarados.

**Resultado:**

- 5 regras de taint e 2 de segredos em `seguranca/semgrep/`, com 27 casos de teste.
- Auditoria do protótipo: 5 vazamentos reais (pergunta e apelido indo crus para o porta-retrato; caminho da URL no log de erro), corrigidos; relatórios de antes e depois em `seguranca/relatorios/`.
- Pipeline `.github/workflows/seguranca.yml` com Semgrep, TruffleHog e `dotnet test`; `.pre-commit-config.yaml` opcional.
- Log de auditoria do filtro (`AuditoriaEmLog`) e 4 testes novos (314 no total).
- Documentação em `docs/cyber/taint-analysis.md`.

**Meu trabalho de validação:**

- Rodei `dotnet build` e `dotnet test`: 314 testes aprovados.
- Conferi no GitHub Actions o pipeline verde no `main` e vermelho no ramo de demonstração com o vazamento.

### Parte 4 · IA na remediação e painel Risco Cidadão · 17/11/2026

**O que eu precisava:** transformar o que o motor e o Semgrep encontram ("PII-CPF-001", "CWE-532") em alertas que a família e quem cuida do app entendem, e um painel executivo que mostre o indicador Risco Cidadão mudando ao vivo.

**Como usei a IA:** pedi apoio para escrever a integração com o Gemini, as conferências antes e depois da IA, as explicações locais de reserva, as rotas novas, o painel em HTML e JavaScript, o script de atividade simulada e os testes.

**Minhas decisões:**

- Usar o Gemini no plano gratuito e guardar a chave só no user-secrets do meu computador.
- A IA é uma saída insegura: recebe só o tipo do dado, o trecho mascarado e o texto com "[CPF removido]", nunca o dado.
- Toda frase da IA passa pelo motor de novo; frase com dado pessoal é trocada pelo texto escrito pela equipe, e o painel mostra quem escreveu cada alerta.
- Sem chave, sem cota ou com a IA fora do ar, a família continua recebendo o alerta (textos locais).
- O painel fica aberto, mas só com números agregados e trechos mascarados, com limite de pedidos por IP.

**Resultado:**

- Rotas `GET /paginas/{id}/explicacao-de-risco`, `GET /risco-cidadao/alertas` e `GET /risco-cidadao/auditoria` (auditoria do Semgrep traduzida: 5 achados antes, 0 depois).
- Painel executivo em `/risco-cidadao/`, servido pela própria API, com gráficos, tabelas, alertas da IA e auditoria; script `seguranca/demo/simular-atividade.ps1` para o vídeo.
- 38 testes novos (352 no total). Os testes acharam um erro na regra de senha ("senha no texto" virava senha), corrigido na versão 1.0.1 das regras.
- Documentação em `docs/cyber/remediacao-ia.md` e bloco M do roteiro (passos 109 a 117).

**Meu trabalho de validação:**

- Rodei `dotnet build` e `dotnet test`: 352 testes aprovados.
- Segui o bloco M do roteiro com e sem a chave do Gemini e conferi que nenhum CPF, telefone ou endereço aparece nas respostas.
- Rodei o script de atividade com o painel aberto e gravei o vídeo.

### Parte 5 · Ajustes, evidências e entrega · 17 e 18/11/2026

**O que eu precisava:** deixar a IA estável no plano gratuito, fechar as evidências e organizar a entrega de Cybersecurity num lugar só.

**Como usei a IA:** pedi apoio para investigar os erros 503 do Gemini, para cobrir o token de login nos prints do Swagger e para escrever o README da pasta `docs/cyber/` e o roteiro do vídeo.

**Minhas decisões:**

- Usar um modelo Flash-Lite como padrão, porque foi o que respondeu no plano gratuito, e repetir uma vez quando o modelo estiver sobrecarregado.
- Cobrir o token de login nos prints, mesmo sendo de uma conta fictícia e só local, porque uma entrega de segurança não deve mostrar credencial.

**Resultado:**

- Modelo padrão `gemini-3.1-flash-lite`, com uma segunda tentativa em caso de 503 e 2 testes novos (354 no total).
- Prints do Swagger com "[token oculto]"; prints do pipeline, da IA e do painel no README.
- `docs/cyber/README.md` com a Ficha, o que foi pedido e onde está, como executar e as evidências.

**Meu trabalho de validação:**

- Investiguei os 503 no terminal da API e testei o Gemini direto pelo PowerShell.
- Rodei `dotnet test` (354 aprovados) e gravei o vídeo do painel com o script de atividade.

---

## 9. Circuito do porta-retrato no Wokwi · 16/11/2026

**O que eu precisava:** um circuito com ESP32 que fosse parte do Me Conta, e não um projeto à parte: a pergunta que a neta manda pelo app tinha que acender a caixinha na casa da avó, e o botão tinha que avisar a família.

**Como usei a IA:** descrevi o porta-retrato que eu queria (uma caixinha bonita, com moldura de LEDs e uma telinha) e pedi apoio para gerar a primeira versão do firmware, do circuito e das mensagens MQTT.

**Minhas decisões:**

- Visual de porta-retrato: anel de LEDs como moldura, com a tela OLED no meio, e um botão grande "quero contar".
- Sensor de luz para o modo noite: brilho baixo e sem som quando a sala está escura.
- Uma chave no circuito só para testar a queda do Wi-Fi durante a demonstração.
- Pelo broker público passam só o apelido, o primeiro nome de quem perguntou e o texto da pergunta.

**Meu trabalho de validação:** rodei no Wokwi cada situação (conexão, pergunta nova com buzzer, pergunta longa com acentos, "quero contar", queda do Wi-Fi com reconexão e modo noite) e tirei os prints de `iot/evidencias/`.

| Problema | Como a IA ajudou | O que eu fiz |
| --- | --- | --- |
| O Wokwi não compilava (`unknown type name 'class'`) | Explicou que o projeto tinha sido criado no modelo em C, e não no de Arduino | Criei o projeto de novo no modelo ESP32 Arduino |
| Erro `'Nota' does not name a type` | Explicou que a IDE cria as declarações das funções antes dos tipos | Movi o tipo para antes da primeira função |
| O Wi-Fi ficava parado no status 0 | Explicou que o status 0 indica conexão sem endereço IP e que o gateway do simulador pode demorar | Comparei com outro projeto que conectava, esperei e confirmei a conexão |
| O MQTT caía com a simulação lenta | Sugeriu um keepalive maior e mensagens mais espaçadas | Ajustei e a conexão ficou estável |
| A moldura parecia marrom no Wokwi | Explicou que o simulador pinta a cor exata do LED | Usei cores mais fortes |

---

## 10. Ponte Node-RED e painel da família · 16/11/2026

**O que eu precisava:** ligar o porta-retrato à API, que roda na minha máquina e não é alcançada pelo Wokwi, e mostrar o lado da família durante a demonstração.

**Como usei a IA:** pedi apoio para gerar a primeira versão do fluxo do Node-RED e do painel, com as chamadas às rotas do aparelho e aos avisos.

**Minhas decisões:**

- Node-RED como ponte entre o MQTT e a API, com as configurações nas variáveis de ambiente da aba.
- Painel com o pacote `node-red-dashboard` clássico, com um botão que faz o mesmo envio de pergunta que o app faz.
- Cores do painel no tom marrom do porta-retrato.

**Meu trabalho de validação:** rodei a API, o Node-RED e o Wokwi juntos: mandei a pergunta da semana pelo painel, vi a moldura acender, apertei "quero contar" e conferi o aviso no painel e na API. Os casos CT36 e CT37 passaram.

| Problema | Como a IA ajudou | O que eu fiz |
| --- | --- | --- |
| "Tipos não reconhecidos" ao importar o fluxo | Explicou que faltava o pacote do painel | Instalei o `node-red-dashboard` pela paleta e importei de novo |
| `ECONNREFUSED` nas chamadas à API | Explicou que a API precisava estar no ar antes | Subi a API e as chamadas passaram |
| `localhost:5080` dava 404 no navegador | Explicou que a API não tem página na raiz | Passei a conferir por `/swagger` e `/health` |
| Títulos e botões se sobrepondo no painel | Sugeriu outro tamanho e disposição para os grupos | Ajustei o layout e as cores e exportei o fluxo final |

---

## 11. Documentação do porta-retrato · 16/11/2026

**Como usei a IA:** pedi apoio para estruturar o README da pasta `iot/` e para ligar cada entregável ao arquivo que o atende em `docs/MATERIAS.md`.

**Meu trabalho:** revisei os textos, escolhi e tirei os prints e conferi os links.

---

## 12. Servidor Linux (Operating Systems) · 16 a 19/11/2026

**Como usei a IA:** pedi apoio para escrever o provisionamento em Bash dividido em etapas (sistema, rede, segurança, aplicação, monitoramento e auditoria), as units do systemd da API e do monitor, o site do nginx, as regras do auditd, o script de teste de falha e o README da pasta `linux/`. Também pedi explicações sobre como o Azure entrega IP e DNS à VM e sobre como guardar segredos fora de variáveis de ambiente.

**Meu trabalho:**
- Criei a VM no Azure for Students, fixei o IP privado na NIC e defini o nome público.
- Escolhi SQLite no servidor por causa da memória da VM e defini os limites de alerta.
- Rodei o provisionamento e o teste de falha na VM, conferi cada recuperação e tirei os prints.
- Revisei os scripts e o README.

---

## Responsabilidade

Todo o código e a documentação foram revisados, executados e testados por mim antes da entrega. Nenhum dado pessoal real foi enviado à IA nem usado no projeto.
