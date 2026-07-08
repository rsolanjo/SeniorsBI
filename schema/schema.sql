-- SeniorsBI — Schema Supabase
-- Rodar no SQL Editor do Supabase: https://ovciyobdpcawghdynqiw.supabase.co

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Metadados por competência (mês)
CREATE TABLE IF NOT EXISTS meses (
  slug        TEXT PRIMARY KEY,        -- '2026-06'
  competencia TEXT NOT NULL,            -- 'Junho / 2026'
  total_chamados INTEGER DEFAULT 0,
  fonte       TEXT DEFAULT 'manual',   -- 'pdf-individual' | 'manual'
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Técnicos por mês
CREATE TABLE IF NOT EXISTS recursos (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mes_slug      TEXT REFERENCES meses(slug) ON DELETE CASCADE,
  nome          TEXT NOT NULL,
  nivel         TEXT,   -- N1 / N2 / N3 / Gestão / LGPD
  equipe        TEXT,
  cap_minutos   INTEGER,
  trab_minutos  INTEGER,
  avulsa_minutos INTEGER DEFAULT 0,
  UNIQUE(mes_slug, nome)
);

-- Horas e chamados por cliente por mês
CREATE TABLE IF NOT EXISTS clientes (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mes_slug      TEXT REFERENCES meses(slug) ON DELETE CASCADE,
  nome          TEXT NOT NULL,
  horas_minutos INTEGER DEFAULT 0,
  chamados      INTEGER DEFAULT 0,
  UNIQUE(mes_slug, nome)
);

-- Premissas de contrato (estático — não muda por mês)
CREATE TABLE IF NOT EXISTS premissas (
  cliente        TEXT PRIMARY KEY,
  franquia_horas INTEGER,
  valor_mensal   NUMERIC(10,2),
  custo_mensal   NUMERIC(10,2)
);

-- Matriz de conhecimento técnico × skill
CREATE TABLE IF NOT EXISTS skills (
  id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tecnico TEXT NOT NULL,
  skill   TEXT NOT NULL,
  nivel   INTEGER CHECK (nivel BETWEEN 1 AND 3),
  UNIQUE(tecnico, skill)
);

-- SLA por mês
CREATE TABLE IF NOT EXISTS sla (
  mes_slug         TEXT PRIMARY KEY REFERENCES meses(slug) ON DELETE CASCADE,
  tma_minutos      INTEGER,
  tmr_minutos      INTEGER,
  dentro_sla_pct   INTEGER,
  chamados_sla     INTEGER,
  chamados_fora    INTEGER
);

-- Satisfação por mês
CREATE TABLE IF NOT EXISTS satisfacao (
  mes_slug   TEXT PRIMARY KEY REFERENCES meses(slug) ON DELETE CASCADE,
  csat       INTEGER,
  nps        INTEGER,
  avaliacoes INTEGER
);

-- Log de arquivos ingeridos (rastreabilidade)
CREATE TABLE IF NOT EXISTS ingest_log (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  arquivo        TEXT NOT NULL,
  mes_slug       TEXT,
  tipo           TEXT,   -- 'indicadores-tecnico' | 'resumo-local' | 'sla' | etc.
  status         TEXT DEFAULT 'pendente',  -- pendente | processado | erro
  erro           TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  processado_at  TIMESTAMPTZ
);

-- Alertas operacionais
CREATE TABLE IF NOT EXISTS alertas (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mes_slug   TEXT REFERENCES meses(slug) ON DELETE CASCADE,
  tipo       TEXT,       -- 'sla' | 'antigo' | 'critico' | 'repetitivo' | 'reaberto'
  titulo     TEXT,
  descricao  TEXT,
  severidade TEXT DEFAULT 'media',  -- baixa | media | alta | critica
  resolvido  BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS desabilitado (ferramenta interna — proteger por Cloudflare Access ou Vercel Auth)
ALTER TABLE meses     DISABLE ROW LEVEL SECURITY;
ALTER TABLE recursos  DISABLE ROW LEVEL SECURITY;
ALTER TABLE clientes  DISABLE ROW LEVEL SECURITY;
ALTER TABLE premissas DISABLE ROW LEVEL SECURITY;
ALTER TABLE skills    DISABLE ROW LEVEL SECURITY;
ALTER TABLE sla       DISABLE ROW LEVEL SECURITY;
ALTER TABLE satisfacao DISABLE ROW LEVEL SECURITY;
ALTER TABLE ingest_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE alertas   DISABLE ROW LEVEL SECURITY;

-- Trigger updated_at em meses
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

CREATE TRIGGER trg_meses_updated
  BEFORE UPDATE ON meses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
