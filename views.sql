use gestao_financ;

-- 1) VIEW: Detalhe de faturas (Receita) com dimensões + data convertida
create or alter view vw_vendas_detalhes 
as
select
	v.invoice_id,
	v.customer_id,
	c.customer_name,
	c.segment,
	c.state,
	v.cost_center_id,
	cc.cost_center_name,
	v.issue_date_id,
	v.due_date_id,
	v.gross_amount,
	v.tax_amount,
	v.net_amount,
	v.paid_flag
from fato_faturas_vendas as v
left join clientes as c on c.customer_id = v.customer_id
left join centro_custos as cc on cc.cost_center_id = v.cost_center_id;

select * from vw_vendas_detalhes;

-- 2) VIEW: Detalhe de contas a pagar (Despesa) com dimensões + data convertida
create or alter view vw_despesas_detalhes
as
select
	c.bill_id,
	c.vendor_id,
	f.vendor_name,
	f.vendor_category,
	c.cost_center_id,
	cc.cost_center_name,
	c.issue_date_id,
	c.due_date_id,
	c.amount,
	c.paid_flag
from fato_compras as c
left join fornecedores as f on c.vendor_id = f.vendor_id
left join centro_custos as cc on cc.cost_center_id = c.cost_center_id;

select * from vw_despesas_detalhes;

-- 3) VIEW: Caixa (transações) com conta + data convertida
create or alter view vw_transacoes_detalhes
as
select
  t.txn_id,
  t.date_id,
  t.date_id AS txn_date,
  d.month_id,
  t.account_id,
  c.account_name,
  c.account_type,
  t.txn_direction,
  t.source_type,
  t.source_id,
  t.amount,
  t.other_type
from transacoes as t
left join dim_date as d on d.date_id = t.date_id
left join contas as c on c.account_id = t.account_id;

select * from vw_transacoes_detalhes;

-- 4) VIEW: Receita mensal
create or alter view vw_receita_mensal
as
select
	d.month_id,
	sum(v.gross_amount) as valor_bruto,
	sum(v.tax_amount) as valor_taxa,
	sum(v.net_amount) as valor_liquida
from fato_faturas_vendas as v
left join dim_date as d on d.date_id = v.issue_date_id
group by d.month_id;

select * from vw_receita_mensal;

-- 5) VIEW: Despesa mensal por centro de custo
create or alter view vw_despesas_mensal_centro_custos
as
select
	d.month_id,
	c.cost_center_id,
	cc.cost_center_name,
	sum(c.amount) as valor_despesa
from fato_compras as c
left join dim_date as d on d.date_id = c.issue_date_id
left join centro_custos as cc on cc.cost_center_id = c.cost_center_id
group by d.month_id, c.cost_center_id, cc.cost_center_name;

select * from vw_despesas_mensal_centro_custos;

-- 6) VIEW: Despesa mensal total
create or alter view vw_despesa_mensal_total
as
select
	month_id,
	sum(valor_despesa) as total_mensal_despesa
from vw_despesas_mensal_centro_custos
group by month_id;

select * from vw_despesa_mensal_total;

-- 7) VIEW: KPIs mensais (margem, lucro operacional)
create or alter view vw_kpis_mensal
as
select
	r.month_id,
	r.valor_liquida,
	d.total_mensal_despesa,
	(r.valor_liquida - d.total_mensal_despesa) as lucro_operacional,
	ROUND(
		 (cast(r.valor_liquida - d.total_mensal_despesa as decimal(18,4)) / nullif(cast(r.valor_liquida as decimal(18,4)), 0)) * 100, 2) as margem_lucro_operacional
from vw_receita_mensal as r
left join vw_despesa_mensal_total as d on d.month_id = r.month_id;
go

select * from vw_kpis_mensal;

-- 8) VIEW: DSO mensal (simplificado)
create or alter view vw_dso_mensal
as
with vendas as (
	select
		invoice_id,
		issue_date_id as data_emissao
	from fato_faturas_vendas
),

transacao AS (
	select
		cast(source_id as int) as invoice_id,
		date_id as data_recebimento
	from transacoes
	where source_type = 'INVOICE' and txn_direction = 'INFLOW'
)

select
	year(t.data_recebimento) as ano,
	month(t.data_recebimento) as mes_recebimento,
	round(AVG(cast(DATEDIFF(DAY, v.data_emissao, t.data_recebimento) as decimal(18, 4))), 2) as dso_dias
from vendas as v
join transacao as t 
	on v.invoice_id = t.invoice_id
group by year(t.data_recebimento), month(t.data_recebimento);
go

select * from vw_dso_mensal;

select * from transacoes;

-- 9) VIEW: DPO mensal (simplificado)
create or alter view vw_dpo_mensal
as
with c as (
	select
		bill_id,
		issue_date_id
	from fato_compras
),

pagar as (
	select
		source_id as bill_id,
		date_id as data_pagamento
	from transacoes
	where source_type = 'BILL'	and txn_direction = 'OUTFLOW'
)

select
	d.date_id,
	year(p.data_pagamento) as ano,
	month(p.data_pagamento) as mes_pagamento,
	ROUND(avg(cast(DATEDIFF(d, c.issue_date_id, p.data_pagamento) as decimal (18, 4))), 2) as dpo_dias
from pagar as p
left join c on c.bill_id = p.bill_id
left join dim_date as d on d.month = month(p.data_pagamento) and d.year = year(p.data_pagamento)
group by year(p.data_pagamento), month(p.data_pagamento), d.date_id;
go

select * from vw_dpo_mensal;

-- 10) VIEW: CCC mensal (DSO - DPO)
create or alter view vw_ccc_mensal
as
select
  dso.ano,
  dso.mes_recebimento,
  dso.dso_dias,
  dpo.dpo_dias,
  ROUND((dso.dso_dias - dpo.dpo_dias), 2) AS ccc_dias
FROM vw_dso_mensal dso
JOIN vw_dpo_mensal dpo on dso.mes_recebimento = dpo.mes_pagamento;
go

select * from vw_ccc_mensal;

-- 11) VIEW: Saldo final mensal (soma do closing_balance do ÚLTIMO dia do mês em todas as contas)
create or alter view vw_balanco_final_mensal
as
WITH last_day AS (
  SELECT
    month_id,
    MAX(date) AS last_date
  FROM dim_date
  GROUP BY month_id
),
last_day_id AS (
  SELECT
    ld.month_id,
    d.date_id
  FROM last_day ld
  JOIN dim_date d
    ON d.month_id = ld.month_id AND d.date = ld.last_date
)
SELECT
 l.month_id,
  SUM(b.closing_balance) AS ending_balance
FROM last_day_id l
JOIN balanco_diario b ON b.date_id = l.date_id
GROUP BY l.month_id;

select * from vw_balanco_final_mensal;


select * from balanco_diario;