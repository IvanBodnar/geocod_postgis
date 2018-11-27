
-------------
SET search_path to public, trabajo;

--drop table calles_geocod;

-- Backup
create table calles_geocod as (

  select * from trabajo.calles_geocod

);

table calles_geocod limit 100;

-- Crea tabla de calles para usar en el geocoder
CREATE TABLE trabajo.calles_geocod AS (
  SELECT gid AS id, codigo, nomoficial AS nombre, alt_ii AS alt_i,
    alt_df AS alt_f, tipo_c AS tipo, geom
  FROM calles
);

-- Restarle 1 a todas las alt_i
update calles_geocod
set alt_i = alt_i - 1
where alt_i > 0;

-- Convertir las columnas que estan en numeric a integer y
-- agregar una columna rango
alter table calles_geocod alter column codigo set data type integer;
alter table calles_geocod alter column alt_i set data type integer;
alter table calles_geocod alter column alt_f set data type integer;
alter table calles_geocod add column rango int4range;
-- Insertar valores en la columna rango, usando alt_i y alt_f
update calles_geocod set rango = (select int4range(alt_i , alt_f) where alt_i < alt_f); --alt_i != 0 and alt_f != 1 and 




-- Pasar nombre y tipo a lower
update calles_geocod set nombre = lower(nombre);
update calles_geocod set tipo = lower(tipo);

table calles_geocod limit 100;

select int4range(alt_i, alt_f)
from calles_geocod
where alt_i != 0 and alt_f != 1
and alt_i < alt_f;

------------------
------------------

------------
-- FUNCIONES
------------


-- Retorna true si la calle existe,
-- NULL si la calle no existe;
CREATE OR REPLACE FUNCTION existe_calle(calle text)
RETURNS BOOL AS $$
DECLARE
  resultado BOOL;
BEGIN
  SELECT lower(calle) IN (SELECT DISTINCT nombre FROM calles_geocod) INTO resultado;
  
  RETURN resultado;
END;
$$ LANGUAGE 'plpgsql';


-- Retorna un int4range con la altura minima y maxima de toda la calle.
-- Es usada en existe_altura() 
CREATE OR REPLACE FUNCTION altura_total_calle(calle text)
RETURNS int4range AS $$
DECLARE
  resultado int4range;
BEGIN
  SELECT int4range(min(alt_i), max(alt_f))
  FROM calles_geocod
  WHERE (alt_i != 0 AND alt_f != 1 AND alt_i < alt_f) AND nombre = calle
  GROUP BY nombre
  INTO resultado;

  RETURN resultado;
END;
$$ LANGUAGE 'plpgsql';


-- Retorna True si la altura ingresada existe en la calle ingresada
-- Usa altura_total_calle()
CREATE OR REPLACE FUNCTION existe_altura(calle text, altura integer)
RETURNS BOOL AS $$
DECLARE
  resultado BOOL;
BEGIN
  SELECT (SELECT altura_total_calle(calle)) @> altura
  INTO resultado;

  RETURN resultado;
END;
$$ LANGUAGE 'plpgsql';


-- Devuelve geometria unida de una calle
CREATE OR REPLACE FUNCTION union_geom(calle text)
  RETURNS geometry AS $$
DECLARE resultado geometry;
BEGIN
  SELECT st_union(array_agg(c.geom))
  FROM calles_geocod c
  WHERE nombre = lower(calle)
  INTO resultado;
  
  RETURN resultado;
END;
$$ LANGUAGE 'plpgsql';


-- Devuelve el punto donde las calles se cruzan o se tocan.
-- Si es resultado es multipoint devuelve el primero.
-- Si no se cruzan o tocan devuelve NULL.
-- Usa union_geom()
CREATE OR REPLACE FUNCTION punto_interseccion(calle1 text, calle2 text)
  RETURNS GEOMETRY AS $$
DECLARE resultado GEOMETRY;
BEGIN
  IF (st_crosses(union_geom(calle1), union_geom(calle2))) OR 
     (st_touches(union_geom(calle1), union_geom(calle2)))
     THEN
     SELECT ST_Intersection(union_geom(calle1), union_geom(calle2)) limit 1
     INTO resultado;
     
     IF st_numgeometries(resultado) > 1
     THEN
     resultado := st_geometryn(resultado, 1);
     END IF;
     
  ELSE
    resultado := NULL;
  END IF;

  RETURN resultado;
END;
$$ LANGUAGE 'plpgsql';


-- Devuelve un punto sobre la altura que se ingresa, exactamente a 
-- la altura relativa de la cuadra.
CREATE OR REPLACE FUNCTION altura_direccion_calle(calle text, altura integer)
  RETURNS GEOMETRY AS
$$
DECLARE resultado GEOMETRY;
BEGIN

  SELECT ST_LineInterpolatePoint(ST_LineMerge((SELECT geom
  FROM calles_geocod
  WHERE rango @> altura
  AND nombre = lower(calle))), (altura % 100)::float / 100)
  INTO resultado;

  RETURN resultado;

END;
$$ LANGUAGE 'plpgsql';

drop function altura_direccion_calle(text, integer);


-- NO ESTA EN USO ACTUALMENTE
-- Devuelve nombre, in4range con la altura total, y geometria unida de una calle
-- Usa union_geom()
-- Para llamar usar select * en vez de select solo -> select * from calle_completa('calle')
CREATE OR REPLACE FUNCTION calle_completa(calle text)
  RETURNS TABLE (
	nombre varchar,
	numeracion int4range
  ) AS
$$
BEGIN
  RETURN QUERY
  select 
  cg.nombre, 
  int4range(min(alt_i), max(alt_f)) as altura
  from calles_geocod cg
  where cg.nombre = calle
  group by cg.nombre;
END;
$$ LANGUAGE 'plpgsql';

select * from calle_completa('vedia');

drop function calle_completa(text);


--------
-- TESTS
--------

select union_geom('vedia');

--select st_intersection(union_geom('monte'), union_geom('paz, gral.'));

select existe_calle('vedia');

select punto_interseccion('garzon, eugenio, gral.', 'araujo');

select altura_direccion_calle('tandil', 3893);

select altura_total_calle('baez');

select existe_altura('moldes', 100);

select altura_direccion_calle('vedia', 1600); -- Tira error porque arroja mas de un resultado

select punto_interseccion('riestra', 'oliden');



table calles_geocod;


select * from calles_geocod where nombre = 'riestra' and rango @> 5301;




select count(*) from calles_geocod
where rango is null;

create table trabajo.cortina_1602 as (
  select 1 as id, altura_calle('cortina', 1602) as geom
);



select ST_LineInterpolatePoint(ST_LineMerge((select geom from calles_geocod
			 where rango @> 3893
			 and nombre = 'TANDIL')), (3893 % 100)::float / 100);


grant usage on schema public  to ivan;



---------
--PRUEBAS
---------

create table prueba as (

  select * from trabajo.calles_geocod

);

update prueba
set alt_i = alt_i - 1
where alt_i > 0;

table prueba;

select * from prueba where id is null;


select nombre, int4range(min(alt_i), max(alt_f)), union_geom('vedia')
from calles_geocod
where nombre = 'vedia'
group by nombre;


create view vistas.riestra_y_oliden as (
select 1 as id, punto_interseccion('riestra', 'murguiondo') as punto
);



--------------------

-- Cuadras repetidas
select nombre, rango
from calles_geocod
group by nombre, rango
having count(*) > 1


