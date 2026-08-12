INSERT INTO measurement_dimensions(code, name, description) VALUES
    ('MASS_FRACTION', 'Mass fraction', 'Mass of analyte per mass of sample'),
    ('MASS', 'Mass', 'Physical mass'),
    ('TEMPERATURE', 'Temperature', 'Thermodynamic temperature expressed for operational use'),
    ('TIME', 'Time', 'Duration')
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    updated_at = now();

INSERT INTO measurement_units(
    dimension_id, code, symbol, conversion_factor, conversion_offset,
    is_canonical, is_active
)
SELECT dimension_record.id, unit_record.code, unit_record.symbol,
       unit_record.factor, unit_record.offset_value,
       unit_record.is_canonical, true
FROM measurement_dimensions dimension_record
JOIN (VALUES
    ('MASS_FRACTION', 'MG_PER_KG', 'mg/kg', 1::numeric, 0::numeric, true),
    ('MASS_FRACTION', 'PPM', 'ppm', 1::numeric, 0::numeric, false),
    ('MASS_FRACTION', 'UG_PER_KG', 'µg/kg', 0.001::numeric, 0::numeric, false),
    ('MASS', 'KG', 'kg', 1::numeric, 0::numeric, true),
    ('MASS', 'G', 'g', 0.001::numeric, 0::numeric, false),
    ('TEMPERATURE', 'C', '°C', 1::numeric, 0::numeric, true),
    ('TEMPERATURE', 'K', 'K', 1::numeric, -273.15::numeric, false),
    ('TIME', 'SECOND', 's', 1::numeric, 0::numeric, true),
    ('TIME', 'MINUTE', 'min', 60::numeric, 0::numeric, false),
    ('TIME', 'HOUR', 'h', 3600::numeric, 0::numeric, false)
) AS unit_record(dimension_code, code, symbol, factor, offset_value, is_canonical)
  ON dimension_record.code = unit_record.dimension_code
ON CONFLICT (code) DO UPDATE SET
    dimension_id = EXCLUDED.dimension_id,
    symbol = EXCLUDED.symbol,
    conversion_factor = EXCLUDED.conversion_factor,
    conversion_offset = EXCLUDED.conversion_offset,
    is_canonical = EXCLUDED.is_canonical,
    is_active = true,
    updated_at = now();

UPDATE measurement_dimensions dimension_record
SET canonical_unit_id = unit_record.id,
    updated_at = now()
FROM measurement_units unit_record
WHERE unit_record.dimension_id = dimension_record.id
  AND unit_record.is_canonical
  AND unit_record.is_active
  AND dimension_record.canonical_unit_id IS DISTINCT FROM unit_record.id;

