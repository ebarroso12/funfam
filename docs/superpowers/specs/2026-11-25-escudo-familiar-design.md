# Escudo Familiar — desenho do projeto

Data: 2026-11-25
Para: Edson Barroso

## Intenção e por quê

App de segurança familiar para acompanhar os filhos menores (Vitor, 7 anos,
e Maria Clara, 12 anos) pelo celular: onde estão, se o aparelho está bem, se
caíram numa rede perigosa, e para agir rápido em caso de roubo ou emergência.
Os pais — Edson e a esposa, os dois como responsáveis plenos desde o início —
recebem os alertas em tempo real e têm o mesmo acesso ao painel. A esposa não
é monitorada: ela é quem monitora, junto com Edson, não uma pessoa vigiada.

Motivação declarada: tranquilidade real sobre a segurança física dos filhos
fora de casa (perder-se, bateria morrer, rede Wi-Fi exposta, roubo do
aparelho), não vigilância do conteúdo da vida social deles.

## Goals

- Localização em tempo real de cada filho, com histórico de trajeto.
- Zonas seguras (casa, escola) com alerta automático quando o filho entra
  ou sai de uma.
- Alerta de bateria crítica e de celular desligado/sem sinal.
- Detecção de Wi-Fi arriscado (rede aberta, sem senha, sem criptografia).
- Tempo de uso por app instalado (quanto tempo, não o conteúdo).
- Botão de pânico no celular do filho, que dispara alerta imediato aos pais
  mesmo com a tela travada e o app fechado — numa emergência real, o filho
  pode não ter tempo de desbloquear o celular.
- Bloqueio remoto de tela, acionado pelos pais a qualquer momento, para o
  caso de roubo ou uso indevido — trava o aparelho até ser destravado com o
  PIN/padrão que os próprios pais configuraram no celular (ver Constraints).
- Painel único para os dois pais, com mapa, histórico e os botões de ação —
  acesso igual para Edson e a esposa, que são responsáveis plenos desde o
  início.
- Corte automático do monitoramento de cada filho na data em que completa
  18 anos (idade vem de um campo de cadastro, protegido por RLS — só os pais
  editam; ver Constraints).

## Non-goals

- Não lê conteúdo de mensagens (WhatsApp, SMS, redes sociais) de ninguém,
  em nenhuma hipótese.
- Não monitora nenhum adulto — nem a esposa, nem qualquer outra pessoa —
  sem o consentimento ativo e informado dela. A esposa participa como
  responsável, não como monitorada.
- Não publica na Play Store nesta fase — instalação por sideload (arquivo
  APK), para não passar pela revisão de políticas de apps de rastreamento
  da Google, que hoje restringe fortemente esse tipo de app.
- Não é um substituto de Family Link/Life360 nessas frentes: não faz
  controle de conteúdo adulto, não faz filtro de navegação, não gerencia
  tempo de tela com bloqueio educativo. Isso fica fora de escopo.

## Anti-goals (o que tornaria isso um fracasso mesmo funcionando)

- Virar, na prática, um app indistinguível de spyware: se alguém o
  encontrar no celular de um filho sem saber o que é, ele precisa estar
  identificável (nome e ícone, mesmo que neutros) — nunca camuflado como
  outra coisa nem escondido da lista de apps.
- Vazar os próprios dados de localização da família por falha de segurança
  do backend (ver Constraints).
- Continuar monitorando um filho depois dos 18 anos por falha ao não
  revisar a idade cadastrada.

## Constraints

- Todos os aparelhos são Android. Não há suporte a iOS neste projeto.
- Backend em Supabase (banco e autenticação), por já ser a stack que Edson
  usa em outros projetos (Alpins, crmclinica, Advisor Goldratt).
- App nativo Android (Kotlin) no celular dos filhos, para rodar em segundo
  plano de forma confiável. Uma versão web/PWA não aguenta localização
  contínua em segundo plano no Android atual.
- O painel dos pais precisa rodar tanto no celular Android quanto no
  Windows (adicionado por Edson em 2026-11-25). Decisão minha: o painel é
  um site web responsivo (não um app nativo separado para cada
  plataforma), acessado pelo navegador em qualquer um dos dois — mais
  simples de construir e manter do que dois apps, e se conecta direto ao
  Supabase. Só o app dos filhos é nativo; o painel dos pais não.
- Localização em segundo plano no Android 10+ exige a permissão
  "permitir todo o tempo", concedida manualmente nas configurações do
  aparelho — não é algo que o app possa conceder a si mesmo.
- O bloqueio remoto de tela (para roubo) exige registrar o app como
  **administrador do dispositivo** (Device Admin) no celular do filho.
  Isso aparece como uma tela de permissão especial na instalação.
- Hoje nenhum dos dois celulares dos filhos tem PIN/padrão configurado.
  O comando de bloqueio remoto (`lockNow`) só trava de forma real se já
  existir um PIN ou padrão no aparelho — sem isso, a tela de bloqueio
  aparece mas é destravada com um simples deslizar. O Android não permite
  que um app configure essa senha à distância (isso mudou a partir do
  Android 7). Por isso, **configurar esse PIN é um passo manual de
  instalação**: os próprios pais o definem direto nas Configurações do
  Android do celular do filho, no momento em que instalam o app, e guardam
  essa senha sem repassar à criança — é ela que garante que só os pais
  conseguem destravar o aparelho depois de um bloqueio remoto.
- O botão de pânico precisa disparar mesmo com a tela travada e o app
  fechado. Isso exige um serviço em segundo plano sempre ativo e, bem
  provavelmente, um atalho/widget acessível já na tela de bloqueio —
  mais trabalho de construção do que um botão dentro do app aberto.
- Sem o app na Play Store, cada atualização precisa ser reinstalada
  manualmente (ou por um mecanismo de auto-update que o app mesmo baixa
  de um link seu — a ser decidido na implementação).
- O banco guarda dados sensíveis (localização de menores). Precisa de
  regras de acesso (RLS no Supabase) que impeçam qualquer pessoa além dos
  dois pais de ler esses dados, e conexão sempre criptografada (HTTPS/TLS).
- Alertas em tempo real chegam por push via Firebase Cloud Messaging —
  decisão minha, por ser o padrão de mercado para esse tipo de notificação
  no Android. Isso significa que alerta de pânico ou de roubo depende de o
  celular ter internet (dados móveis ou Wi-Fi) no momento; esta primeira
  versão não terá um canal de reserva por SMS — decisão minha, para não
  adicionar a complexidade e o custo de uma operadora/gateway de SMS sem
  que isso tenha sido pedido. Fica registrado como limitação conhecida,
  candidata a uma versão futura.
- Cada celular de filho se identifica no banco por uma conta própria,
  criada pelos pais no cadastro — não pelo próprio filho. Decisão minha.
- Histórico de localização é mantido por 180 dias e descartado depois,
  automaticamente — decisão minha, para não acumular risco de vazamento.

## Approaches (decidido)

Três caminhos foram considerados:

1. **App nativo Android + Supabase (escolhido).** Controle total do
   comportamento e dos dados, funciona em segundo plano de forma estável,
   permite bloqueio remoto via Device Admin. Custo: mais trabalho de
   construção, e manutenção é responsabilidade de Edson (sem suporte de
   fornecedor).
2. Combinar apps prontos (Google Family Link + Life360). Zero código, mas
   sem painel personalizado, sem botão de pânico nem bloqueio do jeito
   pedido, e os dados passam pela infraestrutura de terceiros.
3. App leve baseado em navegador/PWA. Mais rápido de montar, mas o Android
   mata esse tipo de processo em segundo plano com frequência — o risco é
   perder justamente o alerta que mais importa.

Escolhida a opção 1, pelos recursos que o Edson pediu (painel próprio,
bloqueio remoto, alertas customizados) não existirem prontos em nenhum
app de mercado combinado.

## O que já foi decidido (pelo Edson, na conversa)

- Filhos monitorados: Vitor (7) e Maria Clara (12). Monitoramento de cada
  um cessa automaticamente aos 18 anos.
- Esposa: responsável plena desde o início, com o mesmo acesso de Edson ao
  painel; nunca é monitorada.
- Nenhum dos celulares dos filhos tem PIN/padrão hoje; será configurado
  pelos pais, manualmente, no momento da instalação.
- Botão de pânico precisa funcionar com a tela travada e o app fechado.
- Sem canal de SMS de reserva nesta primeira versão (decisão minha,
  documentada acima em Constraints); alertas dependem de internet.
- Sem leitura de mensagens, em nenhuma circunstância — linha que não será
  revisitada no projeto.
- Todos os celulares são Android.
- App visível na lista de apps do celular do filho (nome/ícone neutros,
  ex. "Família"), sem notificação a cada evento (diferente de ficar
  oculto/indetectável).
- Bloqueio remoto de tela, não só de apps específicos — para cobrir o caso
  de roubo.

## O que fica para quem construir (plano/execução)

- Nome e ícone exatos do app no celular dos filhos.
- Modelagem exata das tabelas no Supabase e das políticas de RLS.
- Limiares exatos de alerta (ex.: "bateria crítica" = que %, "rede
  arriscada" = quais critérios exatos de Wi-Fi sinalizar).
- Layout do painel dos pais (mapa, lista de alertas, histórico).
- Mecanismo de distribuição do APK aos celulares dos filhos e de futuras
  atualizações.
- Comportamento exato quando o filho revoga manualmente a permissão de
  localização ou desinstala o app (deve gerar alerta aos pais).
- Mecanismo exato do botão de pânico acessível com a tela travada
  (widget na tela de bloqueio, notificação fixa, ou outro recurso do
  Android) e do serviço em segundo plano que o sustenta.
- Texto exato do passo manual de instalação que orienta os pais a
  configurar o PIN/padrão do celular do filho antes de ativar o
  bloqueio remoto.
- Framework exato do painel web (proposta: Next.js/React, hospedado na
  Vercel — mesma stack que Edson já usa em outros projetos) e autenticação
  dos dois pais nele.
