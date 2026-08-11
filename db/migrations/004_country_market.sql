CREATE TABLE countries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    iso2_code char(2) NOT NULL UNIQUE,
    iso3_code char(3) NOT NULL UNIQUE,
    name_en text NOT NULL,
    name_vi text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (iso2_code = upper(iso2_code)),
    CHECK (iso3_code = upper(iso3_code))
);

CREATE TABLE markets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    country_id uuid NOT NULL REFERENCES countries(id) ON DELETE RESTRICT,
    market_type text NOT NULL,
    regulatory_label text,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (code = upper(code))
);

CREATE INDEX idx_markets_country_id ON markets(country_id);

