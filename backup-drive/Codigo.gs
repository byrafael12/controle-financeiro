/**
 * Controle Financeiro: backup mensal automático no Google Drive (Entrega 5.7).
 * Roda no Google Apps Script da conta de Rafael, na nuvem do Google. Não depende do notebook.
 *
 * O que faz, todo dia 1 do mês (entre 8h e 9h, horário de Brasília):
 *   1. Entra no Supabase com o e-mail e a senha guardados nas Propriedades do script.
 *   2. Lê todas as tabelas do app (a RLS só devolve os dados do próprio usuário).
 *   3. Monta o JSON no mesmo formato do botão "Baixar backup" do app (dá para restaurar no app).
 *   4. Grava o arquivo na pasta do Drive informada e confere o tamanho gravado.
 *   5. Marca no app a data do último backup e manda um e-mail com o resumo (ou com o erro).
 *
 * Configuração (uma vez): Configurações do projeto > Propriedades do script:
 *   EMAIL     e-mail de login do app
 *   SENHA     senha de login do app (fica só nesta conta Google; nunca vai para o GitHub)
 *   PASTA_ID  id da pasta do Drive (o trecho final do endereço da pasta)
 * Depois rode uma vez "testarAgora" e uma vez "instalarAgendamento".
 */

const SUPABASE_URL = "https://vktqyguhdgawstlbvwkh.supabase.co";
// Chave pública por definição (publishable). Quem protege os dados é o login + RLS.
const SUPABASE_CHAVE_PUBLICA = "sb_publishable_lAcGjKk6Kn5Yo445pHIUVQ_PykVdfSQ";
const FUSO = "America/Sao_Paulo";

// Tabela do banco -> coleção do app, com os nomes dos campos (banco -> app)
const TABELAS = [
  { tabela: "categorias", colecao: "categorias", chave: "id", ordem: "id",
    campos: { tipo: "tipo", nome: "nome", cor: "cor", ordem: "ordem", ativa: "ativa" } },
  { tabela: "cartoes", colecao: "cartoes", chave: "id", ordem: "id",
    campos: { nome: "nome", dia_melhor_compra: "diaMelhorCompra", dia_vencimento: "diaVencimento", ordem: "ordem", ativo: "ativo" } },
  { tabela: "contas_fixas", colecao: "contasFixas", chave: "id", ordem: "id",
    campos: { descricao: "descricao", categoria_id: "categoriaId", forma_pagamento: "formaPagamento", cartao_id: "cartaoId",
      dia_vencimento: "diaVencimento", valor_estimado_centavos: "valorEstimadoCentavos", ativa: "ativa" } },
  { tabela: "orcamentos", colecao: "orcamentos", chave: "categoria_id", ordem: "categoria_id",
    campos: { valor_planejado_centavos: "valorPlanejadoCentavos" } },
  { tabela: "geracoes", colecao: "geracoes", chave: "mes", ordem: "mes",
    campos: { contas: "contas", atualizado_em: "atualizadoEm" } },
  { tabela: "config", colecao: "config", chave: null, ordem: "user_id",
    campos: { fixas_desde: "fixasDesde", ultimo_backup_baixado: "ultimoBackupBaixado", versao_esquema: "versaoEsquema", criado_em: "criadoEm" } },
  { tabela: "lancamentos", colecao: "lancamentos", chave: "id", ordem: "id",
    campos: { tipo: "tipo", descricao: "descricao", valor_centavos: "valorCentavos", data: "data", competencia: "competencia",
      categoria_id: "categoriaId", forma_pagamento: "formaPagamento", cartao_id: "cartaoId", status: "status", parcela: "parcela",
      grupo_parcela: "grupoParcela", conta_fixa_id: "contaFixaId", reembolso: "reembolso", reembolso_quem: "reembolsoQuem",
      reembolso_de: "reembolsoDe", observacao: "observacao", origem: "origem", versao_esquema: "versaoEsquema",
      criado_em: "criadoEm", atualizado_em: "atualizadoEm" } }
];

/** Agendado: roda todo dia 1. */
function backupMensal() {
  const props = PropertiesService.getScriptProperties();
  const email = props.getProperty("EMAIL");
  try {
    const resumo = fazerBackup(props);
    MailApp.sendEmail(email, "Backup do Controle Financeiro: OK (" + resumo.arquivo + ")",
      "Backup salvo no Google Drive.\n\nArquivo: " + resumo.arquivo + "\nTamanho: " + resumo.tamanho + " bytes\n" +
      "Lançamentos: " + resumo.lancamentos + "\nCategorias: " + resumo.categorias + " · Cartões: " + resumo.cartoes +
      " · Contas fixas: " + resumo.fixas + "\n\nLink da pasta: " + resumo.linkPasta);
  } catch (erro) {
    MailApp.sendEmail(email, "Backup do Controle Financeiro: FALHOU",
      "O backup automático deste mês não foi feito.\n\nMotivo: " + erro.message +
      "\n\nFaça pelo app: Ajustes > Baixar backup completo (JSON), e me mostre esta mensagem.");
    throw erro;
  }
}

/** Para testar na hora, pelo botão Executar. */
function testarAgora() {
  const resumo = fazerBackup(PropertiesService.getScriptProperties());
  Logger.log("OK: " + JSON.stringify(resumo));
}

function fazerBackup(props) {
  const email = props.getProperty("EMAIL");
  const senha = props.getProperty("SENHA");
  const pastaId = props.getProperty("PASTA_ID");
  if (!email || !senha || !pastaId) throw new Error("Faltam EMAIL, SENHA ou PASTA_ID nas Propriedades do script.");

  const sessao = entrar(email, senha);
  try {
    const colecoes = {};
    for (const t of TABELAS) colecoes[t.colecao] = lerTabela(sessao, t);
    if (!colecoes.lancamentos.length) throw new Error("O banco devolveu 0 lançamentos. Backup não gravado, para não guardar um arquivo vazio.");
    if (!colecoes.categorias.length) throw new Error("O banco devolveu 0 categorias. Backup não gravado.");
    conferirLancamentos(colecoes.lancamentos);

    const agora = new Date();
    const dados = { app: "controle-financeiro", versaoEsquema: 1, geradoEm: agora.toISOString(), origem: "backup-automatico-apps-script", colecoes: colecoes };
    const texto = JSON.stringify(dados, null, 1);
    const nome = "backup-controle-financeiro-" + Utilities.formatDate(agora, FUSO, "yyyy-MM-dd") + ".json";

    const pasta = DriveApp.getFolderById(pastaId);
    const arquivo = pasta.createFile(Utilities.newBlob(texto, "application/json", nome));
    const tamanhoGravado = arquivo.getSize();
    const tamanhoEsperado = Utilities.newBlob(texto).getBytes().length;
    if (tamanhoGravado !== tamanhoEsperado) throw new Error("Arquivo gravado com tamanho diferente (" + tamanhoGravado + " de " + tamanhoEsperado + " bytes).");

    marcarUltimoBackup(sessao, agora.toISOString());
    return {
      arquivo: nome, tamanho: tamanhoGravado, lancamentos: colecoes.lancamentos.length, categorias: colecoes.categorias.length,
      cartoes: colecoes.cartoes.length, fixas: colecoes.contasFixas.length, linkPasta: pasta.getUrl()
    };
  } finally {
    sair(sessao);
  }
}

function entrar(email, senha) {
  const r = UrlFetchApp.fetch(SUPABASE_URL + "/auth/v1/token?grant_type=password", {
    method: "post", contentType: "application/json", muteHttpExceptions: true,
    headers: { apikey: SUPABASE_CHAVE_PUBLICA },
    payload: JSON.stringify({ email: email, password: senha })
  });
  if (r.getResponseCode() !== 200) {
    throw new Error("Login no Supabase falhou (código " + r.getResponseCode() + "). Confira EMAIL e SENHA nas Propriedades do script.");
  }
  const corpo = JSON.parse(r.getContentText());
  return { token: corpo.access_token, uid: corpo.user.id };
}

function sair(sessao) {
  try {
    UrlFetchApp.fetch(SUPABASE_URL + "/auth/v1/logout", {
      method: "post", muteHttpExceptions: true,
      headers: { apikey: SUPABASE_CHAVE_PUBLICA, Authorization: "Bearer " + sessao.token }
    });
  } catch (e) { /* sair é só limpeza */ }
}

function cabecalhos(sessao) {
  return { apikey: SUPABASE_CHAVE_PUBLICA, Authorization: "Bearer " + sessao.token };
}

// Lê a tabela inteira em páginas de 1000 (limite do Supabase por pedido)
function lerTabela(sessao, t) {
  const docs = [];
  for (let inicio = 0; ; inicio += 1000) {
    const url = SUPABASE_URL + "/rest/v1/" + t.tabela + "?select=*&order=" + t.ordem + ".asc&limit=1000&offset=" + inicio;
    const r = UrlFetchApp.fetch(url, { method: "get", muteHttpExceptions: true, headers: cabecalhos(sessao) });
    if (r.getResponseCode() !== 200) throw new Error("Não consegui ler " + t.tabela + " (código " + r.getResponseCode() + ").");
    const linhas = JSON.parse(r.getContentText());
    for (const linha of linhas) {
      const doc = { id: t.chave ? linha[t.chave] : "geral" };
      for (const coluna in t.campos) if (coluna in linha) doc[t.campos[coluna]] = linha[coluna];
      docs.push(doc);
    }
    if (linhas.length < 1000) break;
  }
  return docs;
}

function conferirLancamentos(lancs) {
  const ids = {};
  for (const l of lancs) {
    if (ids[l.id]) throw new Error("Lançamento repetido no banco: " + l.id);
    ids[l.id] = true;
    if (!l.tipo || !l.descricao || typeof l.valorCentavos !== "number" || !l.data || !l.competencia || !l.categoriaId || !l.status) {
      throw new Error("Lançamento incompleto: " + l.id);
    }
  }
}

// Faz o app parar de mostrar o lembrete "backup deste mês ainda não foi baixado"
function marcarUltimoBackup(sessao, quando) {
  const r = UrlFetchApp.fetch(SUPABASE_URL + "/rest/v1/config?user_id=eq." + sessao.uid, {
    method: "patch", contentType: "application/json", muteHttpExceptions: true,
    headers: Object.assign(cabecalhos(sessao), { Prefer: "return=minimal" }),
    payload: JSON.stringify({ ultimo_backup_baixado: quando })
  });
  if (r.getResponseCode() >= 300) Logger.log("Aviso: não consegui marcar a data do backup no app (código " + r.getResponseCode() + ").");
}

/** Rode uma vez: cria o agendamento (todo dia 1, entre 8h e 9h de Brasília). Rodar de novo não duplica. */
function instalarAgendamento() {
  for (const g of ScriptApp.getProjectTriggers()) {
    if (g.getHandlerFunction() === "backupMensal") ScriptApp.deleteTrigger(g);
  }
  ScriptApp.newTrigger("backupMensal").timeBased().onMonthDay(1).atHour(8).inTimezone(FUSO).create();
  Logger.log("Agendamento criado: todo dia 1, entre 8h e 9h (horário de Brasília).");
}
