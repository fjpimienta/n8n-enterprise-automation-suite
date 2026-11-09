-- DEV ONLY: fictitious data for two tenants (id_company 1 and 2). No real data, no secrets.
-- Not repeatable: aborts if demo data already exists.
DO $$
DECLARE
  t int; tag text; mail text;
  pu uuid; pad1 uuid; lot uuid; plant uuid; alot uuid; variety uuid; r record; lv uuid; k int; j int;
BEGIN
  IF EXISTS (SELECT 1 FROM production_units WHERE upp_code LIKE '99-%') THEN
    RAISE EXCEPTION 'Demo data already seeded';
  END IF;
  SELECT id INTO variety FROM agri_variety_catalog WHERE variety_code = 'TENERA';

  FOR t IN 1..2 LOOP
    tag  := CASE t WHEN 1 THEN 'A' ELSE 'B' END;
    mail := format('admin.%s@example.test', lower(tag));

    -- Production structure
    INSERT INTO production_units (id_company, upp_code, ranch_name, state_name, municipality_name, tenure_type, total_surface_ha)
    VALUES (t, format('99-001-000%s-001', t), 'DEMO Ranch ' || tag, 'Demo State', 'Demo Municipality', 'PRIVADA', 100 * t)
    RETURNING id INTO pu;
    INSERT INTO production_unit_paddocks (id_company, production_unit_id, paddock_label, area_ha)
    VALUES (t, pu, 'P-1', 20) RETURNING id INTO pad1;
    INSERT INTO production_unit_paddocks (id_company, production_unit_id, paddock_label, area_ha)
    VALUES (t, pu, 'P-2', 30);
    INSERT INTO production_unit_lots (id_company, production_unit_id, lot_name, tenure_type)
    VALUES (t, pu, 'DEMO Lot ' || tag, 'PROPIO') RETURNING id INTO lot;

    -- Livestock: several species
    FOR r IN
      SELECT * FROM (VALUES
        (1,'BOVINO','VACA','CRIA',450),(2,'BOVINO','VACA','CRIA',470),(3,'BOVINO','TORO','REPRODUCCION',620),
        (4,'BOVINO','NOVILLO','ENGORDA',380),(5,'BOVINO','NOVILLONA','CRIA',320),(6,'BOVINO','BECERRO','CRIA',150),
        (7,'BUFALO','BUCERRA','CRIA',140),(8,'BUFALO','BUCERRO','ENGORDA',160),
        (9,'BORREGO','BORREGA','CRIA',45),(10,'BORREGO','BORREGO','ENGORDA',55),
        (11,'EQUIDO','CABALLO','REPRODUCCION',480),(12,'EQUIDO','YEGUA','REPRODUCCION',450)
      ) v(n, species, category, model, w)
    LOOP
      INSERT INTO cattle_livestock (tenant_id, rfid_siniiga, numero_fuego, business_model, category, current_status,
                                    birth_date, species, production_unit_id, paddock_id, lot_id)
      VALUES (t, format('DEMO-%s-%s', tag, lpad(r.n::text, 4, '0')), format('F%s%s', tag, r.n), r.model, r.category,
              'ACTIVO', current_date - (400 + r.n * 30), r.species, pu, pad1, lot)
      RETURNING id INTO lv;
      INSERT INTO cattle_weight_logs (livestock_id, weight_kg, log_date, source_device)
      VALUES (lv, r.w - 20, now() - interval '60 days', 'DEMO'),
             (lv, r.w,      now(),                      'DEMO');
      IF r.n = 1 THEN
        INSERT INTO cattle_sale_income (tenant_id, livestock_id, sale_date, sale_mode, amount, buyer_name, payment_method, banked)
        VALUES (t, lv, current_date - 10, 'POR_PIEZA', 18000 * t, 'DEMO Buyer 1', 'TRANSFERENCIA', true);
      ELSIF r.n = 4 THEN
        INSERT INTO cattle_sale_income (tenant_id, livestock_id, sale_date, sale_mode, amount, weight_kg, price_per_kg, buyer_name, payment_method, banked)
        VALUES (t, lv, current_date - 5, 'POR_KG', 380 * 55, 380, 55, 'DEMO Buyer 2', 'EFECTIVO', false);
      END IF;
    END LOOP;

    INSERT INTO cattle_expenses (tenant_id, expense_date, category, amount, description) VALUES
      (t, current_date - 20, 'ALIMENTO',    5000 * t, 'DEMO feed'),
      (t, current_date - 15, 'MEDICINA',    1200 * t, 'DEMO medicine'),
      (t, current_date - 7,  'COMBUSTIBLE',  800 * t, 'DEMO fuel');

    -- Oil palm
    INSERT INTO agri_plantations (id_company, plantation_code, plantation_name, total_area_ha, tenure)
    VALUES (t, 'DEMO-PAL-' || tag, 'DEMO Palm ' || tag, 50, 'PROPIA') RETURNING id INTO plant;
    FOR k IN 1..2 LOOP
      INSERT INTO agri_lots (id_company, plantation_id, lot_code, lot_name, area_ha, planting_date, variety_id,
                             planting_pattern, water_regime, tenure)
      VALUES (t, plant, 'L' || k, 'DEMO Palm Lot ' || k, 25, current_date - 900, variety, 'TRESBOLILLO', 'TEMPORAL', 'PROPIA')
      RETURNING id INTO alot;
      FOR j IN 1..10 LOOP
        INSERT INTO agri_rows (id_company, lot_id, row_number, planting_positions, alive_plants)
        VALUES (t, alot, j, 20, 18);
      END LOOP;
    END LOOP;
    INSERT INTO agri_expenses (id_company, plantation_id, category_id, expense_date, amount, quantity, unit_code, supplier_name, reported_by_email)
    SELECT t, plant, (SELECT id FROM agri_expense_categories WHERE id_company = t ORDER BY id LIMIT 1),
           current_date - d, 3000 * t, 100, 'KG', 'DEMO Supplier', mail
    FROM unnest(ARRAY[30, 14, 3]) AS d;
  END LOOP;
END $$;
