# Controle Financeiro

App pessoal de controle financeiro de Rafael de Freitas: receitas, despesas, cartões de crédito, compras parceladas, contas fixas, reembolsos e dashboard mensal.

## Como roda hoje

- O app é um único arquivo, `index.html` (HTML, CSS e JavaScript, sem framework).
- Está publicado como artefato privado no claude.ai e só funciona por lá: o banco de dados, o login e o download de arquivos vêm da plataforma (`window.claude.use("db")`, `"user"` e `"downloads"`).
- Aberto direto no navegador, o arquivo mostra a tela "Abra pelo claude.ai" e não acessa nenhum dado.
- Gráficos com [Chart.js 4.4.1](https://www.chartjs.org/docs/latest/).

## O que NÃO está neste repositório

- Nenhum dado financeiro: os lançamentos ficam na área privada da conta Claude, e os backups (JSON) ficam fora do GitHub.
- Nenhuma senha, token ou chave de acesso.

## Organização do código (`index.html`)

1. Configuração (formas de pagamento, paleta, categorias iniciais)
2. Regras de cálculo, sem tela: centavos, competência pela fatura do cartão, parcelas, totais, reembolsos
3. Acesso ao banco (coleções `lancamentos`, `categorias`, `cartoes`, `contasFixas`, `orcamentos`, `geracoes`, `backups`, `config`)
4. Telas: Início, Lançamentos, Fixas e cartões, Ajustes, formulário
5. Gráficos e gestão: orçamento por média de 6 meses, comprometido futuro, backup JSON, exportação CSV, importação
6. Tema claro/escuro e botão + arrastável
7. Inicialização

## Regras principais

- Valores sempre em centavos inteiros (R$ 159,90 = 15990).
- Cartão: fechamento no dia anterior ao melhor dia de compra; a compra conta no mês em que a fatura vence.
- Parcelado: o total é dividido em centavos e a sobra fica na 1ª parcela.
- Contas fixas nascem como previstas (valor médio) e só viram pagas com valor e data confirmados.
- Histórico de jan a set/2026 conta pelo mês da compra; de out/2026 em diante, pela fatura (outubro é mês de transição).

## Próxima fase (Entrega 5, a partir de jan/2027)

App próprio com Supabase (banco e login), seguindo a [OWASP Top 10](https://owasp.org/www-project-top-ten/), com migração dos dados pelo backup JSON.
