\echo Use "CREATE EXTENSION postgis_raster" to load this file. \quit
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
----
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2011 Regina Obe <lr@pcorp.us>
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe <lr@pcorp.us>
--
-- This is a suite of SQL helper functions for use during a PostGIS extension install/upgrade
-- The functions get uninstalled after the extention install/upgrade process
---------------------------
-- postgis_extension_remove_objects: This function removes objects of a particular class from an extension
-- this is needed because there is no ALTER EXTENSION DROP FUNCTION/AGGREGATE command
-- and we can't CREATE OR REPALCe functions whose signatures have changed and we can drop them if they are part of an extention
-- So we use this to remove it from extension first before we drop
CREATE OR REPLACE FUNCTION postgis_extension_remove_objects(param_extension text, param_type text)
  RETURNS boolean AS
$$
DECLARE
	var_sql text := '';
	var_r record;
	var_result boolean := false;
	var_class text := '';
	var_is_aggregate boolean := false;
	var_sql_list text := '';
	var_pgsql_version integer := current_setting('server_version_num');
BEGIN
		var_class := CASE WHEN lower(param_type) = 'function' OR lower(param_type) = 'aggregate' THEN 'pg_proc' ELSE '' END;
		var_is_aggregate := CASE WHEN lower(param_type) = 'aggregate' THEN true ELSE false END;

		IF var_pgsql_version < 110000 THEN
			var_sql_list := $sql$SELECT 'ALTER EXTENSION ' || e.extname || ' DROP ' || $3 || ' ' || COALESCE(proc.proname || '(' || oidvectortypes(proc.proargtypes) || ')' ,typ.typname, cd.relname, op.oprname,
					cs.typname || ' AS ' || ct.typname || ') ', opcname, opfname) || ';' AS remove_command
			FROM pg_depend As d INNER JOIN pg_extension As e
				ON d.refobjid = e.oid INNER JOIN pg_class As c ON
					c.oid = d.classid
					LEFT JOIN pg_proc AS proc ON proc.oid = d.objid
					LEFT JOIN pg_type AS typ ON typ.oid = d.objid
					LEFT JOIN pg_class As cd ON cd.oid = d.objid
					LEFT JOIN pg_operator As op ON op.oid = d.objid
					LEFT JOIN pg_cast AS ca ON ca.oid = d.objid
					LEFT JOIN pg_type AS cs ON ca.castsource = cs.oid
					LEFT JOIN pg_type AS ct ON ca.casttarget = ct.oid
					LEFT JOIN pg_opclass As oc ON oc.oid = d.objid
					LEFT JOIN pg_opfamily As ofa ON ofa.oid = d.objid
			WHERE d.deptype = 'e' and e.extname = $1 and c.relname = $2 AND COALESCE(proc.proisagg, false) = $4;$sql$;
		ELSE -- for PostgreSQL 11 and above, they removed proc.proisagg among others and replaced with some func type thing
			var_sql_list := $sql$SELECT 'ALTER EXTENSION ' || e.extname || ' DROP ' || $3 || ' ' || COALESCE(proc.proname || '(' || oidvectortypes(proc.proargtypes) || ')' ,typ.typname, cd.relname, op.oprname,
					cs.typname || ' AS ' || ct.typname || ') ', opcname, opfname) || ';' AS remove_command
			FROM pg_depend As d INNER JOIN pg_extension As e
				ON d.refobjid = e.oid INNER JOIN pg_class As c ON
					c.oid = d.classid
					LEFT JOIN pg_proc AS proc ON proc.oid = d.objid
					LEFT JOIN pg_type AS typ ON typ.oid = d.objid
					LEFT JOIN pg_class As cd ON cd.oid = d.objid
					LEFT JOIN pg_operator As op ON op.oid = d.objid
					LEFT JOIN pg_cast AS ca ON ca.oid = d.objid
					LEFT JOIN pg_type AS cs ON ca.castsource = cs.oid
					LEFT JOIN pg_type AS ct ON ca.casttarget = ct.oid
					LEFT JOIN pg_opclass As oc ON oc.oid = d.objid
					LEFT JOIN pg_opfamily As ofa ON ofa.oid = d.objid
			WHERE d.deptype = 'e' and e.extname = $1 and c.relname = $2 AND (proc.prokind = 'a')  = $4;$sql$;
		END IF;

		FOR var_r IN EXECUTE var_sql_list  USING param_extension, var_class, param_type, var_is_aggregate
		LOOP
			var_sql := var_sql || var_r.remove_command || ';';
		END LOOP;
		IF var_sql > '' THEN
			EXECUTE var_sql;
			var_result := true;
		END IF;

		RETURN var_result;
END;
$$
LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION postgis_extension_drop_if_exists(param_extension text, param_statement text)
  RETURNS boolean AS
$$
DECLARE
	var_sql_ext text := 'ALTER EXTENSION ' || quote_ident(param_extension) || ' ' || replace(param_statement, 'IF EXISTS', '');
	var_result boolean := false;
BEGIN
	BEGIN
		EXECUTE var_sql_ext;
		var_result := true;
	EXCEPTION
		WHEN OTHERS THEN
			--this is to allow ignoring if the object does not exist in extension
			var_result := false;
	END;
	RETURN var_result;
END;
$$
LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION postgis_extension_AddToSearchPath(a_schema_name varchar)
RETURNS text
AS
$$
DECLARE
	var_result text;
	var_cur_search_path text;
BEGIN
	SELECT reset_val INTO var_cur_search_path FROM pg_settings WHERE name = 'search_path';
	IF var_cur_search_path LIKE '%' || quote_ident(a_schema_name) || '%' THEN
		var_result := a_schema_name || ' already in database search_path';
	ELSE
		var_cur_search_path := var_cur_search_path || ', '
                        || quote_ident(a_schema_name);
		EXECUTE 'ALTER DATABASE ' || quote_ident(current_database())
                              || ' SET search_path = ' || var_cur_search_path;
		var_result := a_schema_name || ' has been added to end of database search_path ';
	END IF;

	EXECUTE 'SET search_path = ' || var_cur_search_path;

  RETURN var_result;
END
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;












-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
--
-- PostGIS Raster - Raster Type for PostGIS
-- http://trac.osgeo.org/postgis/wiki/WKTRaster
--
-- Copyright (c) 2011 Regina Obe <lr@pcorp.us>
-- Copyright (C) 2011 Regents of the University of California
--   <bkpark@ucdavis.edu>
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software Foundation,
-- Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
-- WARNING: Any change in this file must be evaluated for compatibility.
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
-- This section is take add / drop things like CASTS, TYPES etc. that have changed
-- Since these are normally excluded from sed upgrade generator
-- they must be explicitly added
-- So that they can immediately be recreated.
-- It is not run thru the sed processor to prevent it from being stripped
-- Note: We put these in separate file from drop since the extension module has
-- to add additional logic to drop them from the extension as well
--
-- TODO: tag each item with the version in which it was changed
--


















-- drop st_bytea
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP CAST IF EXISTS (raster AS bytea)');
DROP CAST IF EXISTS (raster AS bytea);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bytea(raster)');
DROP FUNCTION IF EXISTS st_bytea(raster);

CREATE OR REPLACE FUNCTION bytea(raster)
    RETURNS bytea
    AS '$libdir/postgis_raster-3', 'RASTER_to_bytea'
    LANGUAGE 'c' IMMUTABLE STRICT;
CREATE CAST (raster AS bytea)
    WITH FUNCTION bytea(raster) AS ASSIGNMENT;

-- drop box2d
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP CAST IF EXISTS (raster AS box2d)');
DROP CAST IF EXISTS (raster AS box2d);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS box2d(raster)');
DROP FUNCTION IF EXISTS box2d(raster);

-- make geometry cast ASSIGNMENT
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP CAST IF EXISTS (raster AS geometry)');
DROP CAST IF EXISTS (raster AS geometry);
CREATE CAST (raster AS geometry)
	WITH FUNCTION st_convexhull(raster) AS ASSIGNMENT;

-- add missing OPERATORs
-- TODO: drop, relying on proc_upgrade.pl output ?
DO LANGUAGE 'plpgsql' $$
BEGIN
	IF NOT EXISTS (
			SELECT
				proname
			FROM pg_proc f
			JOIN pg_type r
				ON r.typname = 'raster'
					AND (f.proargtypes::oid[])[0] = r.oid
			JOIN pg_type g
				ON g.typname = 'geometry'
					AND (f.proargtypes::oid[])[1] = g.oid
			WHERE proname = 'raster_contained_by_geometry'
		) THEN
		CREATE OR REPLACE FUNCTION raster_contained_by_geometry(raster, geometry)
			RETURNS bool
	    AS 'select $1::geometry @ $2'
	    LANGUAGE 'sql' IMMUTABLE STRICT;
		CREATE OPERATOR @ (
			LEFTARG = raster, RIGHTARG = geometry, PROCEDURE = raster_contained_by_geometry,
	    COMMUTATOR = '~',
		  RESTRICT = contsel, JOIN = contjoinsel
		);
	END IF;

	IF NOT EXISTS (
			SELECT
				proname
			FROM pg_proc f
			JOIN pg_type r
				ON r.typname = 'raster'
					AND (f.proargtypes::oid[])[1] = r.oid
			JOIN pg_type g
				ON g.typname = 'geometry'
					AND (f.proargtypes::oid[])[0] = g.oid
			WHERE proname = 'geometry_contained_by_raster'
		) THEN
		CREATE OR REPLACE FUNCTION geometry_contained_by_raster(geometry, raster)
	    RETURNS bool
		  AS 'select $1 @ $2::geometry'
	    LANGUAGE 'sql' IMMUTABLE STRICT;
		CREATE OPERATOR @ (
	    LEFTARG = geometry, RIGHTARG = raster, PROCEDURE = geometry_contained_by_raster,
		  COMMUTATOR = '~',
			RESTRICT = contsel, JOIN = contjoinsel
    );
	END IF;
END;
$$;

--these were renamed to ST_MapAlgebraExpr or argument names changed --
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebra(raster, integer, text, text, nodatavaluerepl text)');
DROP FUNCTION IF EXISTS ST_MapAlgebra(raster, integer, text, text, nodatavaluerepl text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebra(raster, pixeltype text, expression text, nodatavaluerepl text)');
DROP FUNCTION IF EXISTS ST_MapAlgebra(raster, pixeltype text, expression text, nodatavaluerepl text);

--signatures or arg names changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraExpr(raster, integer, text, text, text)');
DROP FUNCTION IF EXISTS ST_MapAlgebraExpr(raster, integer, text, text, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraExpr(raster, text, text, text)');
DROP FUNCTION IF EXISTS ST_MapAlgebraExpr(raster, text, text, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapalgebraFct(raster, regprocedure)');
DROP FUNCTION IF EXISTS ST_MapalgebraFct(raster, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, text, regprocedure, VARIADIC text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, text, regprocedure, VARIADIC text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, text, regprocedure)');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, text, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, regprocedure, VARIADIC text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, regprocedure, VARIADIC text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, regprocedure, variadic text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, regprocedure, variadic text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, text, regprocedure, VARIADIC text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, text, regprocedure, VARIADIC text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, text, regprocedure)');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, text, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, regprocedure, variadic text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, regprocedure, variadic text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapalgebraFct(raster, integer, regprocedure)');
DROP FUNCTION IF EXISTS ST_MapalgebraFct(raster, integer, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, raster, regprocedure, text, text, VARIADIC text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, raster, regprocedure, text, text, VARIADIC text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, raster, integer, regprocedure, text, text, VARIADIC text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFct(raster, integer, raster, integer, regprocedure, text, text, VARIADIC text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_MapAlgebraFctNgb(raster, integer, text, integer, integer, regprocedure, text,  VARIADIC text[])');
DROP FUNCTION IF EXISTS ST_MapAlgebraFctNgb(raster, integer, text, integer, integer, regprocedure, text,  VARIADIC text[]);

--dropped functions
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS  ST_MapAlgebraFct(raster, raster, regprocedure, VARIADIC text[])');
DROP FUNCTION IF EXISTS  ST_MapAlgebraFct(raster, raster, regprocedure, VARIADIC text[]);

--added extra parameter so these are obsolete --
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , double precision , double precision , text , double precision , double precision , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , double precision , double precision , text , double precision , double precision , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , text[] , double precision[] , double precision[] , double precision , double precision , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , text[] , double precision[] , double precision[] , double precision , double precision , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , text , double precision , double precision , double precision , double precision , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , text , double precision , double precision , double precision , double precision , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , integer , integer , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , double precision , double precision , text , double precision , double precision , double precision , double precision , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , double precision , double precision , text , double precision , double precision , double precision , double precision , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_AsRaster(geometry , raster , text , double precision , double precision )');
DROP FUNCTION IF EXISTS ST_AsRaster(geometry , raster , text , double precision , double precision );
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _ST_AsRaster(geometry,double precision , double precision, integer , integer,text[] , double precision[] ,double precision[] ,  double precision,  double precision, double precision,double precision, double precision, double precision,touched boolean)');
DROP FUNCTION IF EXISTS _ST_AsRaster(geometry,double precision , double precision, integer , integer,text[] , double precision[] ,double precision[] ,  double precision,  double precision, double precision,double precision, double precision, double precision,touched boolean);
-- arg names changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _ST_Resample(raster, text, double precision, integer, double precision, double precision, double precision, double precision, double precision, double precision)');
DROP FUNCTION IF EXISTS _ST_Resample(raster, text, double precision, integer, double precision, double precision, double precision, double precision, double precision, double precision);

-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Resample(raster, raster, text, double precision)');
DROP FUNCTION IF EXISTS ST_Resample(raster, raster, text, double precision);

-- default parameters added
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_HasNoBand(raster)');
DROP FUNCTION IF EXISTS ST_HasNoBand(raster);

--function out parameters changed so can not just create or replace
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_BandMetaData(raster, integer)');
DROP FUNCTION IF EXISTS ST_BandMetaData(raster, integer);

--function out parameter changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_BandNoDataValue(raster, integer)');
DROP FUNCTION IF EXISTS ST_BandNoDataValue(raster, integer);
--function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_BandNoDataValue(raster)');
DROP FUNCTION IF EXISTS ST_BandNoDataValue(raster);

--function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_SetGeoReference(raster, text)');
DROP FUNCTION IF EXISTS ST_SetGeoReference(raster, text);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_SetGeoReference(raster, text, text)');
DROP FUNCTION IF EXISTS ST_SetGeoReference(raster, text, text);

--function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_setbandisnodata(raster)');
DROP FUNCTION IF EXISTS st_setbandisnodata(raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_setbandisnodata(raster, integer)');
DROP FUNCTION IF EXISTS st_setbandisnodata(raster, integer);

--function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_setbandnodatavalue(raster, integer, double precision)');
DROP FUNCTION IF EXISTS st_setbandnodatavalue(raster, integer, double precision);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_setbandnodatavalue(raster, integer, double precision, boolean)');
DROP FUNCTION IF EXISTS st_setbandnodatavalue(raster, integer, double precision, boolean);

--function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_dumpaspolygons(raster)');
DROP FUNCTION IF EXISTS st_dumpaspolygons(raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_dumpaspolygons(raster, integer)');
DROP FUNCTION IF EXISTS st_dumpaspolygons(raster, integer);

--function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_polygon(raster)');
DROP FUNCTION IF EXISTS st_polygon(raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_polygon(raster, integer)');
DROP FUNCTION IF EXISTS st_polygon(raster, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_makeemptyraster(int, int, float8, float8, float8, float8, float8, float8)');
DROP FUNCTION IF EXISTS st_makeemptyraster(int, int, float8, float8, float8, float8, float8, float8);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_makeemptyraster(int, int, float8, float8, float8, float8, float8, float8, int4)');
DROP FUNCTION IF EXISTS st_makeemptyraster(int, int, float8, float8, float8, float8, float8, float8, int4);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, text)');
DROP FUNCTION IF EXISTS st_addband(raster, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, text, float8)');
DROP FUNCTION IF EXISTS st_addband(raster, text, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, int, text)');
DROP FUNCTION IF EXISTS st_addband(raster, int, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, int, text, float8)');
DROP FUNCTION IF EXISTS st_addband(raster, int, text, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, raster, int)');
DROP FUNCTION IF EXISTS st_addband(raster, raster, int);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, raster)');
DROP FUNCTION IF EXISTS st_addband(raster, raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, text, float8, float8)');
DROP FUNCTION IF EXISTS st_addband(raster, text, float8, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, int, text, float8, float8)');
DROP FUNCTION IF EXISTS st_addband(raster, int, text, float8, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, raster, int, int)');
DROP FUNCTION IF EXISTS st_addband(raster, raster, int, int);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandisnodata(raster)');
DROP FUNCTION IF EXISTS st_bandisnodata(raster);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandisnodata(raster, integer)');
DROP FUNCTION IF EXISTS st_bandisnodata(raster, integer);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandisnodata(raster, integer, boolean)');
DROP FUNCTION IF EXISTS st_bandisnodata(raster, integer, boolean);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandpath(raster)');
DROP FUNCTION IF EXISTS st_bandpath(raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandpath(raster, integer)');
DROP FUNCTION IF EXISTS st_bandpath(raster, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandpixeltype(raster)');
DROP FUNCTION IF EXISTS st_bandpixeltype(raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandpixeltype(raster, integer)');
DROP FUNCTION IF EXISTS st_bandpixeltype(raster, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, integer, integer)');
DROP FUNCTION IF EXISTS st_value(raster, integer, integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, integer)');
DROP FUNCTION IF EXISTS st_value(raster, integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, geometry)');
DROP FUNCTION IF EXISTS st_value(raster, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, geometry)');
DROP FUNCTION IF EXISTS st_value(raster, geometry);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, integer, integer, boolean)');
DROP FUNCTION IF EXISTS st_value(raster, integer, integer, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, integer, boolean)');
DROP FUNCTION IF EXISTS st_value(raster, integer, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, geometry, boolean)');
DROP FUNCTION IF EXISTS st_value(raster, integer, geometry, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, geometry, boolean)');
DROP FUNCTION IF EXISTS st_value(raster, geometry, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, integer, geometry, double precision)');
DROP FUNCTION IF EXISTS st_value(raster, integer, geometry, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(raster, geometry, double precision)');
DROP FUNCTION IF EXISTS st_value(raster, geometry, double precision);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_georeference(raster)');
DROP FUNCTION IF EXISTS st_georeference(raster);
-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_georeference(raster, text)');
DROP FUNCTION IF EXISTS st_georeference(raster, text);

-- function name change
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS dumpaswktpolygons(raster, integer)');
DROP FUNCTION IF EXISTS dumpaswktpolygons(raster, integer);

-- signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandmetadata(raster, VARIADIC int[])');
DROP FUNCTION IF EXISTS st_bandmetadata(raster, VARIADIC int[]);

--change to use default parameters
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_PixelAsPolygons(raster)');
DROP FUNCTION IF EXISTS ST_PixelAsPolygons(raster);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_PixelAsPolygons(raster,integer)');
DROP FUNCTION IF EXISTS ST_PixelAsPolygons(raster,integer);

-- TYPE summarystats removed in version 2.1.0
-- TODO: only DROP if source version is 2.1.0
-- See http://trac.osgeo.org/postgis/ticket/2908
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_summarystats(raster,int, boolean)');
DROP FUNCTION IF EXISTS st_summarystats(raster,int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_summarystats(raster, boolean)');
DROP FUNCTION IF EXISTS st_summarystats(raster, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(raster,int, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(raster,int, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(raster,int, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(raster,int, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(raster, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(raster, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(raster, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(raster, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_summarystats(text, text,integer, boolean)');
DROP FUNCTION IF EXISTS st_summarystats(text, text,integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_summarystats(text, text, boolean)');
DROP FUNCTION IF EXISTS st_summarystats(text, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text,integer, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text,integer, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text,integer, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text,integer, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, boolean)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_summarystats(raster,int, boolean, double precision)');
DROP FUNCTION IF EXISTS _st_summarystats(raster,int, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_summarystats(text, text,integer, boolean, double precision)');
DROP FUNCTION IF EXISTS _st_summarystats(text, text,integer, boolean, double precision);

-- remove TYPE quantile
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(raster, int, boolean, double precision[])');
DROP FUNCTION IF EXISTS st_quantile(raster, int, boolean, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(raster, int, double precision[])');
DROP FUNCTION IF EXISTS st_quantile(raster, int, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(raster, double precision[])');
DROP FUNCTION IF EXISTS st_quantile(raster, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(raster, int, boolean, double precision, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(raster, int, boolean, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(raster, int, double precision, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(raster, int, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(raster, double precision, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(raster, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(raster, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(raster, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(text, text, int, boolean, double precision[])');
DROP FUNCTION IF EXISTS st_quantile(text, text, int, boolean, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(text, text, int, double precision[])');
DROP FUNCTION IF EXISTS st_quantile(text, text, int, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(text, text, double precision[])');
DROP FUNCTION IF EXISTS st_quantile(text, text, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(text, text, int, boolean, double precision, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(text, text, int, boolean, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(text, text, int, double precision, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(text, text, int, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(text, text, double precision, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(text, text, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(text, text, double precision[])');
DROP FUNCTION IF EXISTS st_approxquantile(text, text, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_quantile(raster, int, boolean, double precision, double precision[])');
DROP FUNCTION IF EXISTS _st_quantile(raster, int, boolean, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_quantile(text, text, int, boolean, double precision, double precision[])');
DROP FUNCTION IF EXISTS _st_quantile(text, text, int, boolean, double precision, double precision[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP TYPE IF EXISTS quantile');
DROP TYPE IF EXISTS quantile;

-- remove TYPE valuecount
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, double precision, double precision)');
DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, double precision, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, boolean, double precision[], double precision)');
DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, boolean, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(text, text, double precision[], double precision)');
DROP FUNCTION IF EXISTS st_valuecount(text, text, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, double precision[], double precision)');
DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, boolean, double precision, double precision)');
DROP FUNCTION IF EXISTS st_valuecount(text, text, integer, boolean, double precision, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(text, text, double precision, double precision)');
DROP FUNCTION IF EXISTS st_valuecount(text, text, double precision, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(raster, integer, boolean, double precision[], double precision)');
DROP FUNCTION IF EXISTS st_valuecount(raster, integer, boolean, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(raster, integer, double precision[], double precision)');
DROP FUNCTION IF EXISTS st_valuecount(raster, integer, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_valuecount(raster, double precision[], double precision)');
DROP FUNCTION IF EXISTS st_valuecount(raster, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_valuecount(text, text, integer, boolean, double precision[], double precision)');
DROP FUNCTION IF EXISTS _st_valuecount(text, text, integer, boolean, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_valuecount(raster, integer, boolean, double precision[], double precision)');
DROP FUNCTION IF EXISTS _st_valuecount(raster, integer, boolean, double precision[], double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP TYPE IF EXISTS valuecount');
DROP TYPE IF EXISTS valuecount;

-- remove TYPE histogram
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(raster, int, boolean, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_histogram(raster, int, boolean, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(raster, int, boolean, int, boolean)');
DROP FUNCTION IF EXISTS st_histogram(raster, int, boolean, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(raster, int, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_histogram(raster, int, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(raster, int, int, boolean)');
DROP FUNCTION IF EXISTS st_histogram(raster, int, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram( raster, int, boolean, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram( raster, int, boolean, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, boolean, double precision, int, boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, boolean, double precision, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, double precision)');
DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(raster, double precision)');
DROP FUNCTION IF EXISTS st_approxhistogram(raster, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, double precision, int, boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(raster, int, double precision, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, int, boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram( text, text, int, boolean, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram( text, text, int, boolean, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, boolean, double precision, int, boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, boolean, double precision, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, double precision)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_histogram( raster, int, boolean, double precision, int, double precision[], boolean, double precision, double precision)');
DROP FUNCTION IF EXISTS _st_histogram( raster, int, boolean, double precision, int, double precision[], boolean, double precision, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_histogram( text, text, int, boolean, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS _st_histogram( text, text, int, boolean, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP TYPE IF EXISTS histogram');
DROP TYPE IF EXISTS histogram;

-- no longer needed functions changed to use out parameters
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP TYPE IF EXISTS bandmetadata');
DROP TYPE IF EXISTS bandmetadata;
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP TYPE IF EXISTS geomvalxy');
DROP TYPE IF EXISTS geomvalxy;

-- raster_columns and raster_overviews tables are deprecated
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _rename_raster_tables()');
DROP FUNCTION IF EXISTS _rename_raster_tables();
CREATE OR REPLACE FUNCTION _rename_raster_tables()
	RETURNS void AS $$
	DECLARE
		cnt int;
	BEGIN
		SELECT count(*) INTO cnt
		FROM pg_class c
		JOIN pg_namespace n
			ON c.relnamespace = n.oid
		WHERE c.relname = 'raster_columns'
			AND c.relkind = 'r'::char
			AND NOT pg_is_other_temp_schema(c.relnamespace);

		IF cnt > 0 THEN
			EXECUTE 'ALTER TABLE raster_columns RENAME TO deprecated_raster_columns';
		END IF;

		SELECT count(*) INTO cnt
		FROM pg_class c
		JOIN pg_namespace n
			ON c.relnamespace = n.oid
		WHERE c.relname = 'raster_overviews'
			AND c.relkind = 'r'::char
			AND NOT pg_is_other_temp_schema(c.relnamespace);

		IF cnt > 0 THEN
			EXECUTE 'ALTER TABLE raster_overviews RENAME TO deprecated_raster_overviews';
		END IF;

	END;
	$$ LANGUAGE 'plpgsql' VOLATILE;
SELECT _rename_raster_tables();
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION _rename_raster_tables()');
DROP FUNCTION _rename_raster_tables();

-- inserted new column into view
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP VIEW IF EXISTS raster_columns');
DROP VIEW IF EXISTS raster_columns;

-- functions no longer supported
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS AddRasterColumn(varchar, varchar, varchar, varchar, integer, varchar[], boolean, boolean, double precision[], double precision, double precision, integer, integer, geometry)');
DROP FUNCTION IF EXISTS AddRasterColumn(varchar, varchar, varchar, varchar, integer, varchar[], boolean, boolean, double precision[], double precision, double precision, integer, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS AddRasterColumn(varchar, varchar, varchar, integer, varchar[], boolean, boolean, double precision[], double precision, double precision, integer, integer, geometry)');
DROP FUNCTION IF EXISTS AddRasterColumn(varchar, varchar, varchar, integer, varchar[], boolean, boolean, double precision[], double precision, double precision, integer, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS AddRasterColumn(varchar, varchar, integer, varchar[], boolean, boolean, double precision[], double precision, double precision, integer, integer, geometry)');
DROP FUNCTION IF EXISTS AddRasterColumn(varchar, varchar, integer, varchar[], boolean, boolean, double precision[], double precision, double precision, integer, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterColumn(varchar, varchar, varchar, varchar)');
DROP FUNCTION IF EXISTS DropRasterColumn(varchar, varchar, varchar, varchar);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterColumn(varchar, varchar, varchar)');
DROP FUNCTION IF EXISTS DropRasterColumn(varchar, varchar, varchar);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterColumn(varchar, varchar)');
DROP FUNCTION IF EXISTS DropRasterColumn(varchar, varchar);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterTable(varchar, varchar, varchar)');
DROP FUNCTION IF EXISTS DropRasterTable(varchar, varchar, varchar);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterTable(varchar, varchar)');
DROP FUNCTION IF EXISTS DropRasterTable(varchar, varchar);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterTable(varchar)');
DROP FUNCTION IF EXISTS DropRasterTable(varchar);

-- function parameters added
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS AddRasterConstraints(name, name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean)');
DROP FUNCTION IF EXISTS AddRasterConstraints(name, name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS AddRasterConstraints(name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean)');
DROP FUNCTION IF EXISTS AddRasterConstraints(name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterConstraints(name, name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean)');
DROP FUNCTION IF EXISTS DropRasterConstraints(name, name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS DropRasterConstraints(name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean)');
DROP FUNCTION IF EXISTS DropRasterConstraints(name, name, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean);

-- function parameters renamed
CREATE OR REPLACE FUNCTION _drop_st_samealignment()
	RETURNS void AS $$
	DECLARE
		cnt int;
	BEGIN
		SELECT count(*) INTO cnt
		FROM pg_proc
		WHERE lower(proname) = 'st_samealignment'
			AND pronargs = 2
			AND (
				proargnames = '{rasta,rastb}'::text[] OR
				proargnames = '{rastA,rastB}'::text[]
			);

		IF cnt > 0 THEN
			RAISE NOTICE 'Dropping ST_SameAlignment(raster, raster) due to parameter name changes.  Unfortunately, this is a DROP ... CASCADE as the alignment raster constraint uses ST_SameAlignment(raster, raster).  You will need to reapply AddRasterConstraint(''SCHEMA'', ''TABLE'', ''COLUMN'', ''alignment'') to any raster column that requires this constraint.';
			DROP FUNCTION IF EXISTS st_samealignment(raster, raster) CASCADE;
		END IF;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE;
SELECT _drop_st_samealignment();
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION _drop_st_samealignment()');
DROP FUNCTION _drop_st_samealignment();

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_intersects(raster, integer, raster, integer)');
DROP FUNCTION IF EXISTS _st_intersects(raster, integer, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersects(raster, integer, raster, integer)');
DROP FUNCTION IF EXISTS st_intersects(raster, integer, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersects(raster, raster)');
DROP FUNCTION IF EXISTS st_intersects(raster, raster);

-- functions have changed dramatically
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, integer, geometry)');
DROP FUNCTION IF EXISTS st_intersection(raster, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, geometry)');
DROP FUNCTION IF EXISTS st_intersection(raster, geometry);

-- function was renamed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_minpossibleval(text)');
DROP FUNCTION IF EXISTS st_minpossibleval(text);

-- function deprecated previously
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_pixelaspolygon(raster, integer, integer, integer)');
DROP FUNCTION IF EXISTS st_pixelaspolygon(raster, integer, integer, integer);

-- function signatures changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, int, geometry, text, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, int, geometry, text, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, int, geometry, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, int, geometry, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, geometry, text, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, geometry, text, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, geometry, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, geometry, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_clip(raster, integer, geometry, boolean)');
DROP FUNCTION IF EXISTS st_clip(raster, integer, geometry, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_clip(raster, geometry, float8, boolean)');
DROP FUNCTION IF EXISTS st_clip(raster, geometry, float8, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_clip(raster, geometry, boolean)');
DROP FUNCTION IF EXISTS st_clip(raster, geometry, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_clip(raster, int, geometry, float8, boolean)');
DROP FUNCTION IF EXISTS st_clip(raster, int, geometry, float8, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_clip(raster, geometry, float8[], boolean)');
DROP FUNCTION IF EXISTS st_clip(raster, geometry, float8[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_clip(raster, integer, geometry, float8[], boolean)');
DROP FUNCTION IF EXISTS st_clip(raster, integer, geometry, float8[], boolean);

-- refactoring of functions
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_dumpaswktpolygons(raster, integer)');
DROP FUNCTION IF EXISTS _st_dumpaswktpolygons(raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP TYPE IF EXISTS wktgeomval');
DROP TYPE IF EXISTS wktgeomval;

-- function parameter names changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_nearestvalue(raster, integer, integer, integer, boolean)');
DROP FUNCTION IF EXISTS st_nearestvalue(raster, integer, integer, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_nearestvalue(raster, integer, integer, boolean)');
DROP FUNCTION IF EXISTS st_nearestvalue(raster, integer, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_neighborhood(raster, integer, integer, integer, integer, boolean)');
DROP FUNCTION IF EXISTS st_neighborhood(raster, integer, integer, integer, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_neighborhood(raster, integer, integer, integer, boolean)');
DROP FUNCTION IF EXISTS st_neighborhood(raster, integer, integer, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_neighborhood(raster, integer, geometry, integer, boolean)');
DROP FUNCTION IF EXISTS st_neighborhood(raster, integer, geometry, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_neighborhood(raster, geometry, integer, boolean)');
DROP FUNCTION IF EXISTS st_neighborhood(raster, geometry, integer, boolean);

-- variants of st_intersection with regprocedure no longer exist
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, integer, raster, integer, text, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, integer, raster, integer, text, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, integer, raster, integer, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, integer, raster, integer, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, raster, text, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, raster, text, regprocedure);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersection(raster, raster, regprocedure)');
DROP FUNCTION IF EXISTS st_intersection(raster, raster, regprocedure);

-- function deprecated
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_pixelaspolygons(raster, integer)');
DROP FUNCTION IF EXISTS st_pixelaspolygons(raster, integer);

-- function deprecated
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandsurface(raster, integer)');
DROP FUNCTION IF EXISTS st_bandsurface(raster, integer);

-- function no longer exist or refactored
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersects(raster, integer, geometry)');
DROP FUNCTION IF EXISTS st_intersects(raster, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersects(raster, geometry, integer)');
DROP FUNCTION IF EXISTS st_intersects(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_intersects(geometry, raster, integer)');
DROP FUNCTION IF EXISTS st_intersects(geometry, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_intersects(raster, geometry, integer)');
DROP FUNCTION IF EXISTS _st_intersects(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_intersects(geometry, raster, integer)');
DROP FUNCTION IF EXISTS _st_intersects(geometry, raster, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_overlaps(geometry, raster, integer)');
DROP FUNCTION IF EXISTS st_overlaps(geometry, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_overlaps(raster, integer, geometry)');
DROP FUNCTION IF EXISTS st_overlaps(raster, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_overlaps(raster, geometry, integer)');
DROP FUNCTION IF EXISTS st_overlaps(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_overlaps(raster, geometry, integer)');
DROP FUNCTION IF EXISTS _st_overlaps(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_overlaps(geometry, raster, integer)');
DROP FUNCTION IF EXISTS _st_overlaps(geometry, raster, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_touches(geometry, raster, integer)');
DROP FUNCTION IF EXISTS st_touches(geometry, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_touches(raster, geometry, integer)');
DROP FUNCTION IF EXISTS st_touches(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_touches(raster, integer, geometry)');
DROP FUNCTION IF EXISTS st_touches(raster, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_touches(geometry, raster, integer)');
DROP FUNCTION IF EXISTS _st_touches(geometry, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_touches(raster, geometry, integer)');
DROP FUNCTION IF EXISTS _st_touches(raster, geometry, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_contains(raster, geometry, integer)');
DROP FUNCTION IF EXISTS st_contains(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_contains(raster, integer, geometry)');
DROP FUNCTION IF EXISTS st_contains(raster, integer, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_contains(geometry, raster, integer)');
DROP FUNCTION IF EXISTS st_contains(geometry, raster, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_contains(raster, geometry, integer)');
DROP FUNCTION IF EXISTS _st_contains(raster, geometry, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_contains(geometry, raster, integer)');
DROP FUNCTION IF EXISTS _st_contains(geometry, raster, integer);

-- function signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_addband(raster, raster[], integer)');
DROP FUNCTION IF EXISTS st_addband(raster, raster[], integer);

-- function signatures changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_slope(raster, integer, text, text, double precision, boolean)');
DROP FUNCTION IF EXISTS st_slope(raster, integer, text, text, double precision, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_slope(raster, integer, text, boolean)');
DROP FUNCTION IF EXISTS st_slope(raster, integer, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_slope(raster, integer, text)');
DROP FUNCTION IF EXISTS st_slope(raster, integer, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_aspect(raster, integer, text, text, boolean)');
DROP FUNCTION IF EXISTS st_aspect(raster, integer, text, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_aspect(raster, integer, text, boolean)');
DROP FUNCTION IF EXISTS st_aspect(raster, integer, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_aspect(raster, integer, text)');
DROP FUNCTION IF EXISTS st_aspect(raster, integer, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_hillshade(raster, integer, text, double precision, double precision, double precision, double precision, boolean)');
DROP FUNCTION IF EXISTS st_hillshade(raster, integer, text, double precision, double precision, double precision, double precision, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_hillshade(raster, integer, text, float, float, float, float, boolean)');
DROP FUNCTION IF EXISTS st_hillshade(raster, integer, text, float, float, float, float, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_hillshade(raster, integer, text, float, float, float, float)');
DROP FUNCTION IF EXISTS st_hillshade(raster, integer, text, float, float, float, float);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_tile(raster, integer, integer, integer[])');
DROP FUNCTION IF EXISTS st_tile(raster, integer, integer, integer[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_tile(raster, integer, integer, integer)');
DROP FUNCTION IF EXISTS st_tile(raster, integer, integer, integer);

-- function signatures changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_setvalue(raster, integer, geometry, double precision)');
DROP FUNCTION IF EXISTS st_setvalue(raster, integer, geometry, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_setvalue(raster, geometry, double precision)');
DROP FUNCTION IF EXISTS st_setvalue(raster, geometry, double precision);

-- function name change
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoord(raster, double precision, double precision)');
DROP FUNCTION IF EXISTS st_world2rastercoord(raster, double precision, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoord(raster, geometry)');
DROP FUNCTION IF EXISTS st_world2rastercoord(raster, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_world2rastercoord(raster, double precision, double precision)');
DROP FUNCTION IF EXISTS _st_world2rastercoord(raster, double precision, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoordx(raster, float8, float8)');
DROP FUNCTION IF EXISTS st_world2rastercoordx(raster, float8, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoordx(raster, float8)');
DROP FUNCTION IF EXISTS st_world2rastercoordx(raster, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoordx(raster, geometry)');
DROP FUNCTION IF EXISTS st_world2rastercoordx(raster, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoordy(raster, float8, float8)');
DROP FUNCTION IF EXISTS st_world2rastercoordy(raster, float8, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoordy(raster, float8)');
DROP FUNCTION IF EXISTS st_world2rastercoordy(raster, float8);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_world2rastercoordy(raster, geometry)');
DROP FUNCTION IF EXISTS st_world2rastercoordy(raster, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_raster2worldcoord( raster, integer, integer)');
DROP FUNCTION IF EXISTS st_raster2worldcoord( raster, integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_raster2worldcoord(raster, integer, integer)');
DROP FUNCTION IF EXISTS _st_raster2worldcoord(raster, integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_raster2worldcoordx(raster, int, int)');
DROP FUNCTION IF EXISTS st_raster2worldcoordx(raster, int, int);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_raster2worldcoordx(raster, int)');
DROP FUNCTION IF EXISTS st_raster2worldcoordx(raster, int);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_raster2worldcoordy(raster, int, int)');
DROP FUNCTION IF EXISTS st_raster2worldcoordy(raster, int, int);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_raster2worldcoordy(raster, int)');
DROP FUNCTION IF EXISTS st_raster2worldcoordy(raster, int);

-- function name change
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_resample(raster, text, double precision, integer, double precision, double precision, double precision, double precision, double precision, double precision, integer, integer)');
DROP FUNCTION IF EXISTS _st_resample(raster, text, double precision, integer, double precision, double precision, double precision, double precision, double precision, double precision, integer, integer);

-- function signatures changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_resample(raster, integer, double precision, double precision, double precision, double precision, double precision, double precision, text, double precision)');
DROP FUNCTION IF EXISTS st_resample(raster, integer, double precision, double precision, double precision, double precision, double precision, double precision, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_resample(raster, integer, integer, integer, double precision, double precision, double precision, double precision, text, double precision)');
DROP FUNCTION IF EXISTS st_resample(raster, integer, integer, integer, double precision, double precision, double precision, double precision, text, double precision);

-- function signatures changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_tile(raster, integer, integer, int[])');
DROP FUNCTION IF EXISTS _st_tile(raster, integer, integer, int[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_tile(raster, integer[], integer, integer)');
DROP FUNCTION IF EXISTS st_tile(raster, integer[], integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_tile(raster, integer, integer, integer)');
DROP FUNCTION IF EXISTS st_tile(raster, integer, integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_tile(raster, integer, integer)');
DROP FUNCTION IF EXISTS st_tile(raster, integer, integer);

-- function no longer exists
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _add_raster_constraint_regular_blocking(name, name, name)');
DROP FUNCTION IF EXISTS _add_raster_constraint_regular_blocking(name, name, name);

-- function signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_asbinary(raster)');
DROP FUNCTION IF EXISTS st_asbinary(raster);

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_aspect4ma(float8[], text, text[])');
DROP FUNCTION IF EXISTS _st_aspect4ma(float8[], text, text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_hillshade4ma(float8[], text, text[])');
DROP FUNCTION IF EXISTS _st_hillshade4ma(float8[], text, text[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_slope4ma(float8[], text, text[])');
DROP FUNCTION IF EXISTS _st_slope4ma(float8[], text, text[]);

-- function signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_gdaldrivers()');
DROP FUNCTION IF EXISTS st_gdaldrivers();

-- function signature change
-- return value changed
DO LANGUAGE 'plpgsql' $$
DECLARE
	cnt bigint;
BEGIN
	SELECT
		count(*)
	INTO cnt
	FROM pg_proc f
	JOIN pg_type t
		ON f.prorettype = t.oid
	WHERE lower(f.proname) = '_raster_constraint_nodata_values'
		AND f.pronargs = 1
		AND t.typname = '_float8'; -- array form

	IF cnt > 0 THEN
		RAISE NOTICE 'Dropping _raster_constraint_nodata_values(raster) due to return value changes.  Unfortunately, this is a DROP ... CASCADE as the NODATA raster constraint uses _raster_constraint_nodata_values(raster).  You will need to reapply AddRasterConstraint(''SCHEMA'', ''TABLE'', ''COLUMN'', ''nodata'') to any raster column that requires this constraint.';
		DROP FUNCTION IF EXISTS _raster_constraint_nodata_values(raster) CASCADE;
	END IF;
END;
$$;

-- 2.5.0 signature changed
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandmetadata(raster, int[])');
DROP FUNCTION IF EXISTS st_bandmetadata(raster, int[]);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_bandmetadata(raster, int)');
DROP FUNCTION IF EXISTS st_bandmetadata(raster, int);

--
-- UPGRADE SCRIPT TO PostGIS 3.2
--

LOAD '$libdir/postgis_raster-3';

DO $$
DECLARE
    old_scripts text;
    new_scripts text;
    old_maj text;
    new_maj text;
    postgis_upgrade_info RECORD;
    postgis_upgrade_info_func_code TEXT;
BEGIN
    --
    -- This uses postgis_lib_version() rather then
    -- postgis_raster_scripts_installed() as in 1.0 because
    -- in the 1.0 => 1.1 transition that would result
    -- in an impossible upgrade:
    --
    --   from 0.3.0 to 1.1.0
    --
    -- Next releases will still be ok as
    -- postgis_lib_version() and postgis_raster_scripts_installed()
    -- would both return actual PostGIS release number.
    --
    BEGIN
        SELECT into old_scripts postgis_raster_lib_version();
    EXCEPTION WHEN OTHERS THEN
        RAISE DEBUG 'Got %', SQLERRM;
        SELECT into old_scripts postgis_raster_scripts_installed();
    END;
    SELECT into new_scripts '3.2';
    SELECT into old_maj substring(old_scripts from 1 for 1);
    SELECT into new_maj substring(new_scripts from 1 for 1);

    -- 2.x to 3.x was upgrade-compatible, see
    -- https://trac.osgeo.org/postgis/ticket/4170#comment:1
    IF new_maj = '3' AND old_maj = '2' THEN
        old_maj = '3'; -- let's pretend old major = new major
    END IF;

    IF old_maj != new_maj THEN
        RAISE EXCEPTION 'Upgrade of postgis_raster from version % to version % requires a dump/reload. See PostGIS manual for instructions', old_scripts, new_scripts;
    END IF;

    WITH versions AS (
      SELECT '3.2'::text as upgraded,
      postgis_raster_scripts_installed() as installed
    ) SELECT
      upgraded as scripts_upgraded,
      installed as scripts_installed,
      substring(upgraded from '([0-9]+)\.')::int * 100 +
      substring(upgraded from '[0-9]+\.([0-9]+)(\.|$)')::int
        as version_to_num,
      substring(installed from '([0-9]+)\.')::int * 100 +
      substring(installed from '[0-9]+\.([0-9]+)(\.|$)')::int
        as version_from_num,
      installed ~ 'dev|alpha|beta'
        as version_from_isdev
      FROM versions INTO postgis_upgrade_info
    ;

    postgis_upgrade_info_func_code := format($func_code$
        CREATE FUNCTION _postgis_upgrade_info(OUT scripts_upgraded TEXT,
                                              OUT scripts_installed TEXT,
                                              OUT version_to_num INT,
                                              OUT version_from_num INT,
                                              OUT version_from_isdev BOOLEAN)
        AS
        $postgis_upgrade_info$
        BEGIN
            scripts_upgraded := %L :: TEXT;
            scripts_installed := %L :: TEXT;
            version_to_num := %L :: INT;
            version_from_num := %L :: INT;
            version_from_isdev := %L :: BOOLEAN;
            RETURN;
        END
        $postgis_upgrade_info$ LANGUAGE 'plpgsql' IMMUTABLE;
        $func_code$,
        postgis_upgrade_info.scripts_upgraded,
        postgis_upgrade_info.scripts_installed,
        postgis_upgrade_info.version_to_num,
        postgis_upgrade_info.version_from_num,
        postgis_upgrade_info.version_from_isdev);
    RAISE DEBUG 'Creating function %', postgis_upgrade_info_func_code;
    EXECUTE postgis_upgrade_info_func_code;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION raster_in(cstring)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_in'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_out(raster)
    RETURNS cstring
    AS '$libdir/postgis_raster-3','RASTER_out'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
-- Type raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 200 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE raster (
    alignment = double,
    internallength = variable,
    input = raster_in,
    output = raster_out,
    storage = extended
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION postgis_raster_lib_version()
    RETURNS text
    AS '$libdir/postgis_raster-3', 'RASTER_lib_version'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE; -- a new lib will require a new session
CREATE OR REPLACE FUNCTION postgis_raster_scripts_installed() RETURNS text
       AS $$ SELECT trim('3.2.0'::text || $rev$ c3e3cc0 $rev$) AS version $$
       LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION postgis_raster_lib_build_date()
    RETURNS text
    AS '$libdir/postgis_raster-3', 'RASTER_lib_build_date'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE; -- a new lib will require a new session
CREATE OR REPLACE FUNCTION postgis_gdal_version()
    RETURNS text
    AS '$libdir/postgis_raster-3', 'RASTER_gdal_version'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Type rastbandarg -- LastUpdated: 201
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 201 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE rastbandarg AS (
	rast raster,
	nband integer
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Type geomval -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 200 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE geomval AS (
	geom geometry,
	val double precision
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION st_envelope(raster)
	RETURNS geometry
	AS '$libdir/postgis_raster-3','RASTER_envelope'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_convexhull(raster)
    RETURNS geometry
    AS '$libdir/postgis_raster-3','RASTER_convex_hull'
    LANGUAGE 'c' IMMUTABLE STRICT
    COST 300;
CREATE OR REPLACE FUNCTION st_minconvexhull(
	rast raster,
	nband integer DEFAULT NULL
)
	RETURNS geometry
	AS '$libdir/postgis_raster-3','RASTER_convex_hull'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION box3d(raster)
    RETURNS box3d
    AS 'select box3d( @extschema@.ST_convexhull($1))'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_height(raster)
    RETURNS integer
    AS '$libdir/postgis_raster-3','RASTER_getHeight'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_numbands(raster)
    RETURNS integer
    AS '$libdir/postgis_raster-3','RASTER_getNumBands'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_scalex(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getXScale'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_scaley(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getYScale'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_skewx(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getXSkew'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_skewy(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getYSkew'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_srid(raster)
    RETURNS integer
    AS '$libdir/postgis_raster-3','RASTER_getSRID'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_upperleftx(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getXUpperLeft'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_upperlefty(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getYUpperLeft'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_width(raster)
    RETURNS integer
    AS '$libdir/postgis_raster-3','RASTER_getWidth'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelwidth(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3', 'RASTER_getPixelWidth'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelheight(raster)
    RETURNS float8
    AS '$libdir/postgis_raster-3', 'RASTER_getPixelHeight'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_geotransform(raster,
    OUT imag double precision,
    OUT jmag double precision,
    OUT theta_i double precision,
    OUT theta_ij double precision,
    OUT xoffset double precision,
    OUT yoffset double precision)
    AS '$libdir/postgis_raster-3', 'RASTER_getGeotransform'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rotation(raster)
    RETURNS float8
    AS $$ SELECT ( @extschema@.ST_Geotransform($1)).theta_i $$
    LANGUAGE 'sql' VOLATILE;
CREATE OR REPLACE FUNCTION st_metadata(
	rast raster,
	OUT upperleftx double precision,
	OUT upperlefty double precision,
	OUT width int,
	OUT height int,
	OUT scalex double precision,
	OUT scaley double precision,
	OUT skewx double precision,
	OUT skewy double precision,
	OUT srid int,
	OUT numbands int
)
	AS '$libdir/postgis_raster-3', 'RASTER_metadata'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_summary(rast raster)
	RETURNS text
	AS $$
	DECLARE
		extent box2d;
		metadata record;
		bandmetadata record;
		msg text;
		msgset text[];
	BEGIN
		extent := @extschema@.ST_Extent(rast::geometry);
		metadata := @extschema@.ST_Metadata(rast);

		msg := 'Raster of ' || metadata.width || 'x' || metadata.height || ' pixels has ' || metadata.numbands || ' ';

		IF metadata.numbands = 1 THEN
			msg := msg || 'band ';
		ELSE
			msg := msg || 'bands ';
		END IF;
		msg := msg || 'and extent of ' || extent;

		IF
			round(metadata.skewx::numeric, 10) <> round(0::numeric, 10) OR
			round(metadata.skewy::numeric, 10) <> round(0::numeric, 10)
		THEN
			msg := 'Skewed ' || overlay(msg placing 'r' from 1 for 1);
		END IF;

		msgset := Array[]::text[] || msg;

		FOR bandmetadata IN SELECT * FROM @extschema@.ST_BandMetadata(rast, ARRAY[]::int[]) LOOP
			msg := 'band ' || bandmetadata.bandnum || ' of pixtype ' || bandmetadata.pixeltype || ' is ';
			IF bandmetadata.isoutdb IS FALSE THEN
				msg := msg || 'in-db ';
			ELSE
				msg := msg || 'out-db ';
			END IF;

			msg := msg || 'with ';
			IF bandmetadata.nodatavalue IS NOT NULL THEN
				msg := msg || 'NODATA value of ' || bandmetadata.nodatavalue;
			ELSE
				msg := msg || 'no NODATA value';
			END IF;

			msgset := msgset || ('    ' || msg);
		END LOOP;

		RETURN array_to_string(msgset, E'\n');
	END;
	$$ LANGUAGE 'plpgsql' STABLE STRICT;
CREATE OR REPLACE FUNCTION ST_MemSize(raster)
	RETURNS int4
	AS '$libdir/postgis_raster-3', 'RASTER_memsize'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_makeemptyraster(width int, height int, upperleftx float8, upperlefty float8, scalex float8, scaley float8, skewx float8, skewy float8, srid int4 DEFAULT 0)
    RETURNS RASTER
    AS '$libdir/postgis_raster-3', 'RASTER_makeEmpty'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_makeemptyraster(width int, height int, upperleftx float8, upperlefty float8, pixelsize float8)
    RETURNS raster
    AS $$ SELECT  @extschema@.ST_makeemptyraster($1, $2, $3, $4, $5, -($5), 0, 0, @extschema@.ST_SRID('POINT(0 0)'::geometry)) $$
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_makeemptyraster(rast raster)
    RETURNS raster
    AS $$
		DECLARE
			w int;
			h int;
			ul_x double precision;
			ul_y double precision;
			scale_x double precision;
			scale_y double precision;
			skew_x double precision;
			skew_y double precision;
			sr_id int;
		BEGIN
			SELECT width, height, upperleftx, upperlefty, scalex, scaley, skewx, skewy, srid INTO w, h, ul_x, ul_y, scale_x, scale_y, skew_x, skew_y, sr_id FROM @extschema@.ST_Metadata(rast);
			RETURN  @extschema@.ST_makeemptyraster(w, h, ul_x, ul_y, scale_x, scale_y, skew_x, skew_y, sr_id);
		END;
    $$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
-- Type addbandarg -- LastUpdated: 201
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 201 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE addbandarg AS (
	index int,
	pixeltype text,
	initialvalue float8,
	nodataval float8
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION st_addband(rast raster, addbandargset addbandarg[])
	RETURNS RASTER
	AS '$libdir/postgis_raster-3', 'RASTER_addBand'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_addband(
	rast raster,
	index int,
	pixeltype text,
	initialvalue float8 DEFAULT 0.,
	nodataval float8 DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT  @extschema@.ST_addband($1, ARRAY[ROW($2, $3, $4, $5)]::addbandarg[]) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_addband(
	rast raster,
	pixeltype text,
	initialvalue float8 DEFAULT 0.,
	nodataval float8 DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT  @extschema@.ST_addband($1, ARRAY[ROW(NULL, $2, $3, $4)]::addbandarg[]) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_addband(
	torast raster,
	fromrast raster,
	fromband int DEFAULT 1,
	torastindex int DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_copyBand'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_addband(
	torast raster,
	fromrasts raster[], fromband integer DEFAULT 1,
	torastindex int DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_addBandRasterArray'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_addband(
	rast raster,
	index int,
	outdbfile text, outdbindex int[],
	nodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_addBandOutDB'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_addband(
	rast raster,
	outdbfile text, outdbindex int[],
	index int DEFAULT NULL,
	nodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_AddBand($1, $4, $2, $3, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_band(rast raster, nbands int[] DEFAULT ARRAY[1])
	RETURNS RASTER
	AS '$libdir/postgis_raster-3', 'RASTER_band'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_band(rast raster, nband int)
	RETURNS RASTER
	AS $$ SELECT  @extschema@.ST_band($1, ARRAY[$2]) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_band(rast raster, nbands text, delimiter char DEFAULT ',')
	RETURNS RASTER
	AS $$ SELECT  @extschema@.ST_band($1, regexp_split_to_array(regexp_replace($2, '[[:space:]]', '', 'g'), E'\\' || array_to_string(regexp_split_to_array($3, ''), E'\\'))::int[]) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
-- Type summarystats -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 200 > version_from_num
OR version_from_num IN ( 201 )     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE summarystats AS (
	count bigint,
	sum double precision,
	mean double precision,
	stddev double precision,
	min double precision,
	max double precision
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_summarystats(
	rast raster,
	nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 1
)
	RETURNS summarystats
	AS '$libdir/postgis_raster-3','RASTER_summaryStats'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_summarystats(
	rast raster,
	nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS summarystats
	AS $$ SELECT @extschema@._ST_summarystats($1, $2, $3, 1) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_summarystats(
	rast raster,
	exclude_nodata_value boolean
)
	RETURNS summarystats
	AS $$ SELECT @extschema@._ST_summarystats($1, 1, $2, 1) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxsummarystats(
	rast raster,
	nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 0.1
)
	RETURNS summarystats
	AS $$ SELECT @extschema@._ST_summarystats($1, $2, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxsummarystats(
	rast raster,
	nband int,
	sample_percent double precision
)
	RETURNS summarystats
	AS $$ SELECT @extschema@._ST_summarystats($1, $2, TRUE, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxsummarystats(
	rast raster,
	exclude_nodata_value boolean,
	sample_percent double precision DEFAULT 0.1
)
	RETURNS summarystats
	AS $$ SELECT @extschema@._ST_summarystats($1, 1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxsummarystats(
	rast raster,
	sample_percent double precision
)
	RETURNS summarystats
	AS $$ SELECT @extschema@._ST_summarystats($1, 1, TRUE, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_summarystats_finalfn(internal)
	RETURNS summarystats
	AS '$libdir/postgis_raster-3', 'RASTER_summaryStats_finalfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_summarystats_transfn(
	internal,
	raster, integer,
	boolean, double precision
)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_summaryStats_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_summarystatsagg(raster,integer,boolean,double precision) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_summarystatsagg(raster, integer, boolean, double precision) (
	SFUNC = _st_summarystats_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_summarystats_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_summarystatsagg(raster,integer,boolean,double precision)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_summarystatsagg(raster, integer, boolean, double precision) (
	SFUNC = _st_summarystats_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_summarystats_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_summarystats_transfn(
	internal,
	raster, boolean, double precision
)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_summaryStats_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_summarystatsagg(raster,boolean,double precision) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_summarystatsagg(raster, boolean, double precision) (
	SFUNC = _st_summarystats_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_summarystats_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_summarystatsagg(raster,boolean,double precision)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_summarystatsagg(raster, boolean, double precision) (
	SFUNC = _st_summarystats_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_summarystats_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_summarystats_transfn(
	internal,
	raster, int, boolean
)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_summaryStats_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_summarystatsagg(raster,int,boolean) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_summarystatsagg(raster, int, boolean) (
	SFUNC = _st_summarystats_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_summarystats_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_summarystatsagg(raster,int,boolean)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_summarystatsagg(raster, int, boolean) (
	SFUNC = _st_summarystats_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_summarystats_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_count(rast raster, nband int DEFAULT 1, exclude_nodata_value boolean DEFAULT TRUE, sample_percent double precision DEFAULT 1)
	RETURNS bigint
	AS $$
	DECLARE
		rtn bigint;
	BEGIN
		IF exclude_nodata_value IS FALSE THEN
			SELECT width * height INTO rtn FROM @extschema@.ST_Metadata(rast);
		ELSE
			SELECT count INTO rtn FROM @extschema@._ST_summarystats($1, $2, $3, $4);
		END IF;

		RETURN rtn;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_count(rast raster, nband int DEFAULT 1, exclude_nodata_value boolean DEFAULT TRUE)
	RETURNS bigint
	AS $$ SELECT @extschema@._ST_count($1, $2, $3, 1) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_count(rast raster, exclude_nodata_value boolean)
	RETURNS bigint
	AS $$ SELECT @extschema@._ST_count($1, 1, $2, 1) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxcount(rast raster, nband int DEFAULT 1, exclude_nodata_value boolean DEFAULT TRUE, sample_percent double precision DEFAULT 0.1)
	RETURNS bigint
	AS $$ SELECT @extschema@._ST_count($1, $2, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxcount(rast raster, nband int, sample_percent double precision)
	RETURNS bigint
	AS $$ SELECT @extschema@._ST_count($1, $2, TRUE, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxcount(rast raster, exclude_nodata_value boolean, sample_percent double precision DEFAULT 0.1)
	RETURNS bigint
	AS $$ SELECT @extschema@._ST_count($1, 1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxcount(rast raster, sample_percent double precision)
	RETURNS bigint
	AS $$ SELECT @extschema@._ST_count($1, 1, TRUE, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
-- Type agg_count -- LastUpdated: 202
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 202 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE agg_count AS (
	count bigint,
	nband integer,
	exclude_nodata_value boolean,
	sample_percent double precision
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_countagg_finalfn(agg agg_count)
	RETURNS bigint
	AS $$
	BEGIN
		IF agg IS NULL THEN
			RAISE EXCEPTION 'Cannot count coverage';
		END IF;

		RETURN agg.count;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION __st_countagg_transfn(
	agg agg_count,
	rast raster,
 	nband integer DEFAULT 1, exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 1
)
	RETURNS agg_count
	AS $$
	DECLARE
		_count bigint;
		rtn_agg agg_count;
	BEGIN

		-- only process parameter args once
		IF agg IS NULL THEN
			rtn_agg.count := 0;

			IF nband < 1 THEN
				RAISE EXCEPTION 'Band index must be greater than zero (1-based)';
			ELSE
				rtn_agg.nband := nband;
			END IF;

			IF exclude_nodata_value IS FALSE THEN
				rtn_agg.exclude_nodata_value := FALSE;
			ELSE
				rtn_agg.exclude_nodata_value := TRUE;
			END IF;

			IF sample_percent < 0. OR sample_percent > 1. THEN
				RAISE EXCEPTION 'Sample percent must be between zero and one';
			ELSE
				rtn_agg.sample_percent := sample_percent;
			END IF;
		ELSE
			rtn_agg := agg;
		END IF;

		IF rast IS NOT NULL THEN
			IF rtn_agg.exclude_nodata_value IS FALSE THEN
				SELECT width * height INTO _count FROM @extschema@.ST_Metadata(rast);
			ELSE
				SELECT count INTO _count FROM @extschema@._ST_summarystats(
					rast,
				 	rtn_agg.nband, rtn_agg.exclude_nodata_value,
					rtn_agg.sample_percent
				);
			END IF;
		END IF;

		rtn_agg.count := rtn_agg.count + _count;
		RETURN rtn_agg;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_countagg_transfn(
	agg agg_count,
	rast raster,
 	nband integer, exclude_nodata_value boolean,
	sample_percent double precision
)
	RETURNS agg_count
	AS $$
	DECLARE
		rtn_agg agg_count;
	BEGIN
		rtn_agg :=  @extschema@.__st_countagg_transfn(
			agg,
			rast,
			nband, exclude_nodata_value,
			sample_percent
		);
		RETURN rtn_agg;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_countagg(raster,integer,boolean,double precision) -- LastUpdated: 202
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_countagg(raster, integer, boolean, double precision) (
	SFUNC = _st_countagg_transfn,
	STYPE = agg_count,
	parallel = safe,
	FINALFUNC = _st_countagg_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 202 > version_from_num OR (
      202 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_countagg(raster,integer,boolean,double precision)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_countagg(raster, integer, boolean, double precision) (
	SFUNC = _st_countagg_transfn,
	STYPE = agg_count,
	parallel = safe,
	FINALFUNC = _st_countagg_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_countagg_transfn(
	agg agg_count,
	rast raster,
 	nband integer, exclude_nodata_value boolean
)
	RETURNS agg_count
	AS $$
	DECLARE
		rtn_agg agg_count;
	BEGIN
		rtn_agg :=  @extschema@.__ST_countagg_transfn(
			agg,
			rast,
			nband, exclude_nodata_value,
			1
		);
		RETURN rtn_agg;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_countagg(raster,integer,boolean) -- LastUpdated: 202
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_countagg(raster, integer, boolean) (
	SFUNC = _st_countagg_transfn,
	STYPE = agg_count,
	parallel = safe,
	FINALFUNC = _st_countagg_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 202 > version_from_num OR (
      202 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_countagg(raster,integer,boolean)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_countagg(raster, integer, boolean) (
	SFUNC = _st_countagg_transfn,
	STYPE = agg_count,
	parallel = safe,
	FINALFUNC = _st_countagg_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_countagg_transfn(
	agg agg_count,
	rast raster,
 	exclude_nodata_value boolean
)
	RETURNS agg_count
	AS $$
	DECLARE
		rtn_agg agg_count;
	BEGIN
		rtn_agg :=  @extschema@.__ST_countagg_transfn(
			agg,
			rast,
			1, exclude_nodata_value,
			1
		);
		RETURN rtn_agg;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_countagg(raster,boolean) -- LastUpdated: 202
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_countagg(raster, boolean) (
	SFUNC = _st_countagg_transfn,
	STYPE = agg_count,
	parallel = safe,
	FINALFUNC = _st_countagg_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 202 > version_from_num OR (
      202 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_countagg(raster,boolean)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_countagg(raster, boolean) (
	SFUNC = _st_countagg_transfn,
	STYPE = agg_count,
	parallel = safe,
	FINALFUNC = _st_countagg_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_histogram(
	rast raster, nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 1,
	bins int DEFAULT 0, width double precision[] DEFAULT NULL,
	right boolean DEFAULT FALSE,
	min double precision DEFAULT NULL, max double precision DEFAULT NULL,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS '$libdir/postgis_raster-3','RASTER_histogram'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_histogram(
	rast raster, nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	bins int DEFAULT 0, width double precision[] DEFAULT NULL,
	right boolean DEFAULT FALSE,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, $3, 1, $4, $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_histogram(
	rast raster, nband int,
	exclude_nodata_value boolean,
	bins int,
	right boolean,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, $3, 1, $4, NULL, $5) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_histogram(
	rast raster, nband int,
	bins int, width double precision[] DEFAULT NULL,
	right boolean DEFAULT FALSE,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, TRUE, 1, $3, $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_histogram(
	rast raster, nband int,
	bins int,
	right boolean,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, TRUE, 1, $3, NULL, $4) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxhistogram(
	rast raster, nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 0.1,
	bins int DEFAULT 0, width double precision[] DEFAULT NULL,
	right boolean DEFAULT FALSE,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, $3, $4, $5, $6, $7) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxhistogram(
	rast raster, nband int,
	exclude_nodata_value boolean,
	sample_percent double precision,
	bins int,
	right boolean,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, $3, $4, $5, NULL, $6) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxhistogram(
	rast raster, nband int,
	sample_percent double precision,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, TRUE, $3, 0, NULL, FALSE) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxhistogram(
	rast raster,
	sample_percent double precision,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, 1, TRUE, $2, 0, NULL, FALSE) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxhistogram(
	rast raster, nband int,
	sample_percent double precision,
	bins int, width double precision[] DEFAULT NULL,
	right boolean DEFAULT FALSE,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, TRUE, $3, $4, $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxhistogram(
	rast raster, nband int,
	sample_percent double precision,
	bins int, right boolean,
	OUT min double precision,
	OUT max double precision,
	OUT count bigint,
	OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT min, max, count, percent FROM @extschema@._ST_histogram($1, $2, TRUE, $3, $4, NULL, $5) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_quantile(
	rast raster,
	nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 1,
	quantiles double precision[] DEFAULT NULL,
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS '$libdir/postgis_raster-3','RASTER_quantile'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(
	rast raster,
	nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	quantiles double precision[] DEFAULT NULL,
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, $2, $3, 1, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(
	rast raster,
	nband int,
	quantiles double precision[],
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, $2, TRUE, 1, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(
	rast raster,
	quantiles double precision[],
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, 1, TRUE, 1, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(rast raster, nband int, exclude_nodata_value boolean, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, $2, $3, 1, ARRAY[$4]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(rast raster, nband int, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, $2, TRUE, 1, ARRAY[$3]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(rast raster, exclude_nodata_value boolean, quantile double precision DEFAULT NULL)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, 1, $2, 1, ARRAY[$3]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_quantile(rast raster, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, 1, TRUE, 1, ARRAY[$2]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(
	rast raster,
	nband int DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	sample_percent double precision DEFAULT 0.1,
	quantiles double precision[] DEFAULT NULL,
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, $2, $3, $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(
	rast raster,
	nband int,
	sample_percent double precision,
	quantiles double precision[] DEFAULT NULL,
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, $2, TRUE, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(
	rast raster,
	sample_percent double precision,
	quantiles double precision[] DEFAULT NULL,
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, 1, TRUE, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(
	rast raster,
	quantiles double precision[],
	OUT quantile double precision,
	OUT value double precision
)
	RETURNS SETOF record
	AS $$ SELECT @extschema@._ST_quantile($1, 1, TRUE, 0.1, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(rast raster, nband int, exclude_nodata_value boolean, sample_percent double precision, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, $2, $3, $4, ARRAY[$5]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(rast raster, nband int, sample_percent double precision, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, $2, TRUE, $3, ARRAY[$4]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(rast raster, sample_percent double precision, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, 1, TRUE, $2, ARRAY[$3]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(rast raster, exclude_nodata_value boolean, quantile double precision DEFAULT NULL)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, 1, $2, 0.1, ARRAY[$3]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_approxquantile(rast raster, quantile double precision)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_quantile($1, 1, TRUE, 0.1, ARRAY[$2]::double precision[])).value $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_valuecount(
	rast raster, nband integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	searchvalues double precision[] DEFAULT NULL,
	roundto double precision DEFAULT 0,
	OUT value double precision,
	OUT count integer,
	OUT percent double precision
)
	RETURNS SETOF record
	AS '$libdir/postgis_raster-3', 'RASTER_valueCount'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuecount(
	rast raster, nband integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	searchvalues double precision[] DEFAULT NULL,
	roundto double precision DEFAULT 0,
	OUT value double precision, OUT count integer
)
	RETURNS SETOF record
	AS $$ SELECT value, count FROM @extschema@._ST_valuecount($1, $2, $3, $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuecount(rast raster, nband integer, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT count integer)
	RETURNS SETOF record
	AS $$ SELECT value, count FROM @extschema@._ST_valuecount($1, $2, TRUE, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuecount(rast raster, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT count integer)
	RETURNS SETOF record
	AS $$ SELECT value, count FROM @extschema@._ST_valuecount($1, 1, TRUE, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuecount(rast raster, nband integer, exclude_nodata_value boolean, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS integer
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, $3, ARRAY[$4]::double precision[], $5)).count $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuecount(rast raster, nband integer, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS integer
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, TRUE, ARRAY[$3]::double precision[], $4)).count $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuecount(rast raster, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS integer
	AS $$ SELECT ( @extschema@._ST_valuecount($1, 1, TRUE, ARRAY[$2]::double precision[], $3)).count $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuepercent(
	rast raster, nband integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	searchvalues double precision[] DEFAULT NULL,
	roundto double precision DEFAULT 0,
	OUT value double precision, OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT value, percent FROM @extschema@._ST_valuecount($1, $2, $3, $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuepercent(rast raster, nband integer, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT percent double precision)
	RETURNS SETOF record
	AS $$ SELECT value, percent FROM @extschema@._ST_valuecount($1, $2, TRUE, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuepercent(rast raster, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT percent double precision)
	RETURNS SETOF record
	AS $$ SELECT value, percent FROM @extschema@._ST_valuecount($1, 1, TRUE, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuepercent(rast raster, nband integer, exclude_nodata_value boolean, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, $3, ARRAY[$4]::double precision[], $5)).percent $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuepercent(rast raster, nband integer, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, TRUE, ARRAY[$3]::double precision[], $4)).percent $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_valuepercent(rast raster, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_valuecount($1, 1, TRUE, ARRAY[$2]::double precision[], $3)).percent $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_valuecount(
	rastertable text,
	rastercolumn text,
	nband integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	searchvalues double precision[] DEFAULT NULL,
	roundto double precision DEFAULT 0,
	OUT value double precision,
	OUT count integer,
	OUT percent double precision
)
	RETURNS SETOF record
	AS '$libdir/postgis_raster-3', 'RASTER_valueCountCoverage'
	LANGUAGE 'c' STABLE;
CREATE OR REPLACE FUNCTION st_valuecount(
	rastertable text, rastercolumn text,
	nband integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	searchvalues double precision[] DEFAULT NULL,
	roundto double precision DEFAULT 0,
	OUT value double precision, OUT count integer
)
	RETURNS SETOF record
	AS $$ SELECT value, count FROM @extschema@._ST_valuecount($1, $2, $3, $4, $5, $6) $$
	LANGUAGE 'sql' STABLE;
CREATE OR REPLACE FUNCTION st_valuecount(rastertable text, rastercolumn text, nband integer, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT count integer)
	RETURNS SETOF record
	AS $$ SELECT value, count FROM @extschema@._ST_valuecount($1, $2, $3, TRUE, $4, $5) $$
	LANGUAGE 'sql' STABLE;
CREATE OR REPLACE FUNCTION st_valuecount(rastertable text, rastercolumn text, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT count integer)
	RETURNS SETOF record
	AS $$ SELECT value, count FROM @extschema@._ST_valuecount($1, $2, 1, TRUE, $3, $4) $$
	LANGUAGE 'sql' STABLE;
CREATE OR REPLACE FUNCTION st_valuecount(rastertable text, rastercolumn text, nband integer, exclude_nodata_value boolean, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS integer
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, $3, $4, ARRAY[$5]::double precision[], $6)).count $$
	LANGUAGE 'sql' STABLE STRICT;
CREATE OR REPLACE FUNCTION st_valuecount(rastertable text, rastercolumn text, nband integer, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS integer
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, $3, TRUE, ARRAY[$4]::double precision[], $5)).count $$
	LANGUAGE 'sql' STABLE STRICT;
CREATE OR REPLACE FUNCTION st_valuecount(rastertable text, rastercolumn text, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS integer
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, 1, TRUE, ARRAY[$3]::double precision[], $4)).count $$
	LANGUAGE 'sql' STABLE STRICT;
CREATE OR REPLACE FUNCTION st_valuepercent(
	rastertable text, rastercolumn text,
	nband integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE,
	searchvalues double precision[] DEFAULT NULL,
	roundto double precision DEFAULT 0,
	OUT value double precision, OUT percent double precision
)
	RETURNS SETOF record
	AS $$ SELECT value, percent FROM @extschema@._ST_valuecount($1, $2, $3, $4, $5, $6) $$
	LANGUAGE 'sql' STABLE;
CREATE OR REPLACE FUNCTION st_valuepercent(rastertable text, rastercolumn text, nband integer, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT percent double precision)
	RETURNS SETOF record
	AS $$ SELECT value, percent FROM @extschema@._ST_valuecount($1, $2, $3, TRUE, $4, $5) $$
	LANGUAGE 'sql' STABLE;
CREATE OR REPLACE FUNCTION st_valuepercent(rastertable text, rastercolumn text, searchvalues double precision[], roundto double precision DEFAULT 0, OUT value double precision, OUT percent double precision)
	RETURNS SETOF record
	AS $$ SELECT value, percent FROM @extschema@._ST_valuecount($1, $2, 1, TRUE, $3, $4) $$
	LANGUAGE 'sql' STABLE;
CREATE OR REPLACE FUNCTION st_valuepercent(rastertable text, rastercolumn text, nband integer, exclude_nodata_value boolean, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, $3, $4, ARRAY[$5]::double precision[], $6)).percent $$
	LANGUAGE 'sql' STABLE STRICT;
CREATE OR REPLACE FUNCTION st_valuepercent(rastertable text, rastercolumn text, nband integer, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, $3, TRUE, ARRAY[$4]::double precision[], $5)).percent $$
	LANGUAGE 'sql' STABLE STRICT;
CREATE OR REPLACE FUNCTION st_valuepercent(rastertable text, rastercolumn text, searchvalue double precision, roundto double precision DEFAULT 0)
	RETURNS double precision
	AS $$ SELECT ( @extschema@._ST_valuecount($1, $2, 1, TRUE, ARRAY[$3]::double precision[], $4)).percent $$
	LANGUAGE 'sql' STABLE STRICT;
-- Type reclassarg -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 200 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE reclassarg AS (
	nband int,
	reclassexpr text,
	pixeltype text,
	nodataval double precision
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_reclass(rast raster, VARIADIC reclassargset reclassarg[])
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_reclass'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_reclass(rast raster, VARIADIC reclassargset reclassarg[])
	RETURNS raster
	AS $$
	DECLARE
		i int;
		expr text;
	BEGIN
		-- for each reclassarg, validate elements as all except nodataval cannot be NULL
		FOR i IN SELECT * FROM generate_subscripts($2, 1) LOOP
			IF $2[i].nband IS NULL OR $2[i].reclassexpr IS NULL OR $2[i].pixeltype IS NULL THEN
				RAISE WARNING 'Values are required for the nband, reclassexpr and pixeltype attributes.';
				RETURN rast;
			END IF;
		END LOOP;

		RETURN @extschema@._ST_reclass($1, VARIADIC $2);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_reclass(rast raster, nband int, reclassexpr text, pixeltype text, nodataval double precision DEFAULT NULL)
	RETURNS raster
	AS $$ SELECT st_reclass($1, ROW($2, $3, $4, $5)) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_reclass(rast raster, reclassexpr text, pixeltype text)
	RETURNS raster
	AS $$ SELECT st_reclass($1, ROW(1, $2, $3, NULL)) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_colormap(
	rast raster, nband int,
	colormap text,
	method text DEFAULT 'INTERPOLATE'
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_colorMap'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_colormap(
	rast raster, nband int DEFAULT 1,
	colormap text DEFAULT 'grayscale',
	method text DEFAULT 'INTERPOLATE'
)
	RETURNS raster
	AS $$
	DECLARE
		_ismap boolean;
		_colormap text;
		_element text[];
	BEGIN
		_ismap := TRUE;

		-- clean colormap to see what it is
		_colormap := split_part(colormap, E'\n', 1);
		_colormap := regexp_replace(_colormap, E':+', ' ', 'g');
		_colormap := regexp_replace(_colormap, E',+', ' ', 'g');
		_colormap := regexp_replace(_colormap, E'\\t+', ' ', 'g');
		_colormap := regexp_replace(_colormap, E' +', ' ', 'g');
		_element := regexp_split_to_array(_colormap, ' ');

		-- treat as colormap
		IF (array_length(_element, 1) > 1) THEN
			_colormap := colormap;
		-- treat as keyword
		ELSE
			method := 'INTERPOLATE';
			CASE lower(trim(both from _colormap))
				WHEN 'grayscale', 'greyscale' THEN
					_colormap := '
100%   0
  0% 254
  nv 255
					';
				WHEN 'pseudocolor' THEN
					_colormap := '
100% 255   0   0 255
 50%   0 255   0 255
  0%   0   0 255 255
  nv   0   0   0   0
					';
				WHEN 'fire' THEN
					_colormap := '
  100% 243 255 221 255
93.75% 242 255 178 255
 87.5% 255 255 135 255
81.25% 255 228  96 255
   75% 255 187  53 255
68.75% 255 131   7 255
 62.5% 255  84   0 255
56.25% 255  42   0 255
   50% 255   0   0 255
43.75% 255  42   0 255
 37.5% 224  74   0 255
31.25% 183  91   0 255
   25% 140  93   0 255
18.75%  99  82   0 255
 12.5%  58  58   1 255
 6.25%  12  15   0 255
    0%   0   0   0 255
    nv   0   0   0   0
					';
				WHEN 'bluered' THEN
					_colormap := '
100.00% 165   0  33 255
 94.12% 216  21  47 255
 88.24% 247  39  53 255
 82.35% 255  61  61 255
 76.47% 255 120  86 255
 70.59% 255 172 117 255
 64.71% 255 214 153 255
 58.82% 255 241 188 255
 52.94% 255 255 234 255
 47.06% 234 255 255 255
 41.18% 188 249 255 255
 35.29% 153 234 255 255
 29.41% 117 211 255 255
 23.53%  86 176 255 255
 17.65%  61 135 255 255
 11.76%  40  87 255 255
  5.88%  24  28 247 255
  0.00%  36   0 216 255
     nv   0   0   0   0
					';
				ELSE
					RAISE EXCEPTION 'Unknown colormap keyword: %', colormap;
			END CASE;
		END IF;

		RETURN @extschema@._ST_colormap($1, $2, _colormap, $4);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_colormap(
	rast raster,
	colormap text,
	method text DEFAULT 'INTERPOLATE'
)
	RETURNS RASTER
	AS $$ SELECT @extschema@.ST_ColorMap($1, 1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_fromgdalraster(gdaldata bytea, srid integer DEFAULT NULL)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_fromGDALRaster'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_gdaldrivers(
	OUT idx int,
	OUT short_name text,
	OUT long_name text,
	OUT can_read boolean,
	OUT can_write boolean,
	OUT create_options text
)
  RETURNS SETOF record
	AS '$libdir/postgis_raster-3', 'RASTER_getGDALDrivers'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asgdalraster(rast raster, format text, options text[] DEFAULT NULL, srid integer DEFAULT NULL)
	RETURNS bytea
	AS '$libdir/postgis_raster-3', 'RASTER_asGDALRaster'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_Contour(
		rast raster,
		bandnumber integer DEFAULT 1,
		level_interval float8 DEFAULT 100.0,
		level_base float8 DEFAULT 0.0,
		fixed_levels float8[] DEFAULT ARRAY[]::float8[],
		polygonize boolean DEFAULT false
		)
	RETURNS table(geom geometry, id integer, value float8)
	AS '$libdir/postgis_raster-3', 'RASTER_Contour'
	LANGUAGE 'c'
	IMMUTABLE STRICT
	PARALLEL SAFE
	COST 10000;
CREATE OR REPLACE FUNCTION ST_InterpolateRaster(
		geom geometry,
		options text,
		rast raster,
		bandnumber integer DEFAULT 1
		)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_InterpolateRaster'
	LANGUAGE 'c'
	IMMUTABLE STRICT
	PARALLEL SAFE
	COST 10000;
CREATE OR REPLACE FUNCTION st_astiff(rast raster, options text[] DEFAULT NULL, srid integer DEFAULT NULL)
	RETURNS bytea
	AS $$
	DECLARE
		i int;
		num_bands int;
		nodata double precision;
		last_nodata double precision;
	BEGIN
		IF rast IS NULL THEN
			RETURN NULL;
		END IF;

		num_bands := st_numbands($1);

		-- TIFF only allows one NODATA value for ALL bands
		FOR i IN 1..num_bands LOOP
			nodata := st_bandnodatavalue($1, i);
			IF last_nodata IS NULL THEN
				last_nodata := nodata;
			ELSEIF nodata != last_nodata THEN
				RAISE NOTICE 'The TIFF format only permits one NODATA value for all bands.  The value used will be the last band with a NODATA value.';
			END IF;
		END LOOP;

		RETURN st_asgdalraster($1, 'GTiff', $2, $3);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_astiff(rast raster, nbands int[], options text[] DEFAULT NULL, srid integer DEFAULT NULL)
	RETURNS bytea
	AS $$ SELECT st_astiff(st_band($1, $2), $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_astiff(rast raster, compression text, srid integer DEFAULT NULL)
	RETURNS bytea
	AS $$
	DECLARE
		compression2 text;
		c_type text;
		c_level int;
		i int;
		num_bands int;
		options text[];
	BEGIN
		IF rast IS NULL THEN
			RETURN NULL;
		END IF;

		compression2 := trim(both from upper(compression));

		IF length(compression2) > 0 THEN
			-- JPEG
			IF position('JPEG' in compression2) != 0 THEN
				c_type := 'JPEG';
				c_level := substring(compression2 from '[0-9]+$');

				IF c_level IS NOT NULL THEN
					IF c_level > 100 THEN
						c_level := 100;
					ELSEIF c_level < 1 THEN
						c_level := 1;
					END IF;

					options := array_append(options, 'JPEG_QUALITY=' || c_level);
				END IF;

				-- per band pixel type check
				num_bands := st_numbands($1);
				FOR i IN 1..num_bands LOOP
					IF @extschema@.ST_BandPixelType($1, i) != '8BUI' THEN
						RAISE EXCEPTION 'The pixel type of band % in the raster is not 8BUI.  JPEG compression can only be used with the 8BUI pixel type.', i;
					END IF;
				END LOOP;

			-- DEFLATE
			ELSEIF position('DEFLATE' in compression2) != 0 THEN
				c_type := 'DEFLATE';
				c_level := substring(compression2 from '[0-9]+$');

				IF c_level IS NOT NULL THEN
					IF c_level > 9 THEN
						c_level := 9;
					ELSEIF c_level < 1 THEN
						c_level := 1;
					END IF;

					options := array_append(options, 'ZLEVEL=' || c_level);
				END IF;

			ELSE
				c_type := compression2;

				-- CCITT
				IF position('CCITT' in compression2) THEN
					-- per band pixel type check
					num_bands := st_numbands($1);
					FOR i IN 1..num_bands LOOP
						IF @extschema@.ST_BandPixelType($1, i) != '1BB' THEN
							RAISE EXCEPTION 'The pixel type of band % in the raster is not 1BB.  CCITT compression can only be used with the 1BB pixel type.', i;
						END IF;
					END LOOP;
				END IF;

			END IF;

			-- compression type check
			IF ARRAY[c_type] <@ ARRAY['JPEG', 'LZW', 'PACKBITS', 'DEFLATE', 'CCITTRLE', 'CCITTFAX3', 'CCITTFAX4', 'NONE'] THEN
				options := array_append(options, 'COMPRESS=' || c_type);
			ELSE
				RAISE NOTICE 'Unknown compression type: %.  The outputted TIFF will not be COMPRESSED.', c_type;
			END IF;
		END IF;

		RETURN st_astiff($1, options, $3);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_astiff(rast raster, nbands int[], compression text, srid integer DEFAULT NULL)
	RETURNS bytea
	AS $$ SELECT st_astiff(st_band($1, $2), $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asjpeg(rast raster, options text[] DEFAULT NULL)
	RETURNS bytea
	AS $$
	DECLARE
		rast2 @extschema@.raster;
		num_bands int;
		i int;
	BEGIN
		IF rast IS NULL THEN
			RETURN NULL;
		END IF;

		num_bands := st_numbands($1);

		-- JPEG allows 1 or 3 bands
		IF num_bands <> 1 AND num_bands <> 3 THEN
			RAISE NOTICE 'The JPEG format only permits one or three bands.  The first band will be used.';
			rast2 := st_band(rast, ARRAY[1]);
			num_bands := st_numbands(rast);
		ELSE
			rast2 := rast;
		END IF;

		-- JPEG only supports 8BUI pixeltype
		FOR i IN 1..num_bands LOOP
			IF @extschema@.ST_BandPixelType(rast, i) != '8BUI' THEN
				RAISE EXCEPTION 'The pixel type of band % in the raster is not 8BUI.  The JPEG format can only be used with the 8BUI pixel type.', i;
			END IF;
		END LOOP;

		RETURN st_asgdalraster(rast2, 'JPEG', $2, NULL);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asjpeg(rast raster, nbands int[], options text[] DEFAULT NULL)
	RETURNS bytea
	AS $$ SELECT st_asjpeg(st_band($1, $2), $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asjpeg(rast raster, nbands int[], quality int)
	RETURNS bytea
	AS $$
	DECLARE
		quality2 int;
		options text[];
	BEGIN
		IF quality IS NOT NULL THEN
			IF quality > 100 THEN
				quality2 := 100;
			ELSEIF quality < 10 THEN
				quality2 := 10;
			ELSE
				quality2 := quality;
			END IF;

			options := array_append(options, 'QUALITY=' || quality2);
		END IF;

		RETURN @extschema@.st_asjpeg(st_band($1, $2), options);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asjpeg(rast raster, nband int, options text[] DEFAULT NULL)
	RETURNS bytea
	AS $$ SELECT @extschema@.st_asjpeg(st_band($1, $2), $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asjpeg(rast raster, nband int, quality int)
	RETURNS bytea
	AS $$ SELECT @extschema@.st_asjpeg($1, ARRAY[$2], $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspng(rast raster, options text[] DEFAULT NULL)
	RETURNS bytea
	AS $$
	DECLARE
		rast2 @extschema@.raster;
		num_bands int;
		i int;
		pt text;
	BEGIN
		IF rast IS NULL THEN
			RETURN NULL;
		END IF;

		num_bands := st_numbands($1);

		-- PNG allows 1, 3 or 4 bands
		IF num_bands <> 1 AND num_bands <> 3 AND num_bands <> 4 THEN
			RAISE NOTICE 'The PNG format only permits one, three or four bands.  The first band will be used.';
			rast2 := @extschema@.st_band($1, ARRAY[1]);
			num_bands := @extschema@.st_numbands(rast2);
		ELSE
			rast2 := rast;
		END IF;

		-- PNG only supports 8BUI and 16BUI pixeltype
		FOR i IN 1..num_bands LOOP
			pt = @extschema@.ST_BandPixelType(rast, i);
			IF pt != '8BUI' AND pt != '16BUI' THEN
				RAISE EXCEPTION 'The pixel type of band % in the raster is not 8BUI or 16BUI.  The PNG format can only be used with 8BUI and 16BUI pixel types.', i;
			END IF;
		END LOOP;

		RETURN @extschema@.st_asgdalraster(rast2, 'PNG', $2, NULL);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspng(rast raster, nbands int[], options text[] DEFAULT NULL)
	RETURNS bytea
	AS $$ SELECT @extschema@.st_aspng(st_band($1, $2), $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspng(rast raster, nbands int[], compression int)
	RETURNS bytea
	AS $$
	DECLARE
		compression2 int;
		options text[];
	BEGIN
		IF compression IS NOT NULL THEN
			IF compression > 9 THEN
				compression2 := 9;
			ELSEIF compression < 1 THEN
				compression2 := 1;
			ELSE
				compression2 := compression;
			END IF;

			options := array_append(options, 'ZLEVEL=' || compression2);
		END IF;

		RETURN @extschema@.st_aspng(st_band($1, $2), options);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspng(rast raster, nband int, options text[] DEFAULT NULL)
	RETURNS bytea
	AS $$ SELECT @extschema@.st_aspng(st_band($1, $2), $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspng(rast raster, nband int, compression int)
	RETURNS bytea
	AS $$ SELECT @extschema@.st_aspng($1, ARRAY[$2], $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_asraster(
	geom geometry,
	scalex double precision DEFAULT 0, scaley double precision DEFAULT 0,
	width integer DEFAULT 0, height integer DEFAULT 0,
	pixeltype text[] DEFAULT ARRAY['8BUI']::text[],
	value double precision[] DEFAULT ARRAY[1]::double precision[],
	nodataval double precision[] DEFAULT ARRAY[0]::double precision[],
	upperleftx double precision DEFAULT NULL, upperlefty double precision DEFAULT NULL,
	gridx double precision DEFAULT NULL, gridy double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_asRaster'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	scalex double precision, scaley double precision,
	gridx double precision DEFAULT NULL, gridy double precision DEFAULT NULL,
	pixeltype text[] DEFAULT ARRAY['8BUI']::text[],
	value double precision[] DEFAULT ARRAY[1]::double precision[],
	nodataval double precision[] DEFAULT ARRAY[0]::double precision[],
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, $2, $3, NULL, NULL, $6, $7, $8, NULL, NULL, $4, $5, $9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	scalex double precision, scaley double precision,
	pixeltype text[],
	value double precision[] DEFAULT ARRAY[1]::double precision[],
	nodataval double precision[] DEFAULT ARRAY[0]::double precision[],
	upperleftx double precision DEFAULT NULL, upperlefty double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, $2, $3, NULL, NULL, $4, $5, $6, $7, $8, NULL, NULL,	$9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	width integer, height integer,
	gridx double precision DEFAULT NULL, gridy double precision DEFAULT NULL,
	pixeltype text[] DEFAULT ARRAY['8BUI']::text[],
	value double precision[] DEFAULT ARRAY[1]::double precision[],
	nodataval double precision[] DEFAULT ARRAY[0]::double precision[],
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, NULL, NULL, $2, $3, $6, $7, $8, NULL, NULL, $4, $5, $9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	width integer, height integer,
	pixeltype text[],
	value double precision[] DEFAULT ARRAY[1]::double precision[],
	nodataval double precision[] DEFAULT ARRAY[0]::double precision[],
	upperleftx double precision DEFAULT NULL, upperlefty double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, NULL, NULL, $2, $3, $4, $5, $6, $7, $8, NULL, NULL,	$9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	scalex double precision, scaley double precision,
	gridx double precision, gridy double precision,
	pixeltype text,
	value double precision DEFAULT 1,
	nodataval double precision DEFAULT 0,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, $2, $3, NULL, NULL, ARRAY[$6]::text[], ARRAY[$7]::double precision[], ARRAY[$8]::double precision[], NULL, NULL, $4, $5, $9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	scalex double precision, scaley double precision,
	pixeltype text,
	value double precision DEFAULT 1,
	nodataval double precision DEFAULT 0,
	upperleftx double precision DEFAULT NULL, upperlefty double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, $2, $3, NULL, NULL, ARRAY[$4]::text[], ARRAY[$5]::double precision[], ARRAY[$6]::double precision[], $7, $8, NULL, NULL, $9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	width integer, height integer,
	gridx double precision, gridy double precision,
	pixeltype text,
	value double precision DEFAULT 1,
	nodataval double precision DEFAULT 0,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, NULL, NULL, $2, $3, ARRAY[$6]::text[], ARRAY[$7]::double precision[], ARRAY[$8]::double precision[], NULL, NULL, $4, $5, $9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	width integer, height integer,
	pixeltype text,
	value double precision DEFAULT 1,
	nodataval double precision DEFAULT 0,
	upperleftx double precision DEFAULT NULL, upperlefty double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_asraster($1, NULL, NULL, $2, $3, ARRAY[$4]::text[], ARRAY[$5]::double precision[], ARRAY[$6]::double precision[], $7, $8, NULL, NULL,$9, $10, $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	ref raster,
	pixeltype text[] DEFAULT ARRAY['8BUI']::text[],
	value double precision[] DEFAULT ARRAY[1]::double precision[],
	nodataval double precision[] DEFAULT ARRAY[0]::double precision[],
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$
	DECLARE
		g @extschema@.geometry;
		g_srid integer;

		ul_x double precision;
		ul_y double precision;
		scale_x double precision;
		scale_y double precision;
		skew_x double precision;
		skew_y double precision;
		sr_id integer;
	BEGIN
		SELECT upperleftx, upperlefty, scalex, scaley, skewx, skewy, srid INTO ul_x, ul_y, scale_x, scale_y, skew_x, skew_y, sr_id FROM @extschema@.ST_Metadata(ref);
		--RAISE NOTICE '%, %, %, %, %, %, %', ul_x, ul_y, scale_x, scale_y, skew_x, skew_y, sr_id;

		-- geometry and raster has different SRID
		g_srid := @extschema@.ST_SRID(geom);
		IF g_srid != sr_id THEN
			RAISE NOTICE 'The geometry''s SRID (%) is not the same as the raster''s SRID (%).  The geometry will be transformed to the raster''s projection', g_srid, sr_id;
			g := @extschema@.ST_Transform(geom, sr_id);
		ELSE
			g := geom;
		END IF;

		RETURN @extschema@._ST_asraster(g, scale_x, scale_y, NULL, NULL, $3, $4, $5, NULL, NULL, ul_x, ul_y, skew_x, skew_y, $6);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asraster(
	geom geometry,
	ref raster,
	pixeltype text,
	value double precision DEFAULT 1,
	nodataval double precision DEFAULT 0,
	touched boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT  @extschema@.ST_AsRaster($1, $2, ARRAY[$3]::text[], ARRAY[$4]::double precision[], ARRAY[$5]::double precision[], $6) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _ST_gdalwarp(
	rast raster,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125,
	srid integer DEFAULT NULL,
	scalex double precision DEFAULT 0, scaley double precision DEFAULT 0,
	gridx double precision DEFAULT NULL, gridy double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	width integer DEFAULT NULL, height integer DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_GDALWarp'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resample(
	rast raster,
	scalex double precision DEFAULT 0, scaley double precision DEFAULT 0,
	gridx double precision DEFAULT NULL, gridy double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $8,	$9, NULL, $2, $3, $4, $5, $6, $7) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resample(
	rast raster,
	width integer, height integer,
	gridx double precision DEFAULT NULL, gridy double precision DEFAULT NULL,
	skewx double precision DEFAULT 0, skewy double precision DEFAULT 0,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $8,	$9, NULL, NULL, NULL, $4, $5, $6, $7, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resample(
	rast raster,
	ref raster,
	algorithm text DEFAULT 'NearestNeighbour',
	maxerr double precision DEFAULT 0.125,
	usescale boolean DEFAULT TRUE
)
	RETURNS raster
	AS $$
	DECLARE
		rastsrid int;

		_srid int;
		_dimx int;
		_dimy int;
		_scalex double precision;
		_scaley double precision;
		_gridx double precision;
		_gridy double precision;
		_skewx double precision;
		_skewy double precision;
	BEGIN
		SELECT srid, width, height, scalex, scaley, upperleftx, upperlefty, skewx, skewy INTO _srid, _dimx, _dimy, _scalex, _scaley, _gridx, _gridy, _skewx, _skewy FROM st_metadata($2);

		rastsrid := @extschema@.ST_SRID($1);

		-- both rasters must have the same SRID
		IF (rastsrid != _srid) THEN
			RAISE EXCEPTION 'The raster to be resampled has a different SRID from the reference raster';
			RETURN NULL;
		END IF;

		IF usescale IS TRUE THEN
			_dimx := NULL;
			_dimy := NULL;
		ELSE
			_scalex := NULL;
			_scaley := NULL;
		END IF;

		RETURN @extschema@._ST_gdalwarp($1, $3, $4, NULL, _scalex, _scaley, _gridx, _gridy, _skewx, _skewy, _dimx, _dimy);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resample(
	rast raster,
	ref raster,
	usescale boolean,
	algorithm text DEFAULT 'NearestNeighbour',
	maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$ SELECT @extschema@.st_resample($1, $2, $4, $5, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_transform(rast raster, srid integer, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125, scalex double precision DEFAULT 0, scaley double precision DEFAULT 0)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $3, $4, $2, $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_transform(rast raster, srid integer, scalex double precision, scaley double precision, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $5, $6, $2, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_transform(rast raster, srid integer, scalexy double precision, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $4, $5, $2, $3, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_transform(
	rast raster,
	alignto raster,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$
	DECLARE
		_srid integer;
		_scalex double precision;
		_scaley double precision;
		_gridx double precision;
		_gridy double precision;
		_skewx double precision;
		_skewy double precision;
	BEGIN
		SELECT srid, scalex, scaley, upperleftx, upperlefty, skewx, skewy INTO _srid, _scalex, _scaley, _gridx, _gridy, _skewx, _skewy FROM st_metadata($2);

		RETURN @extschema@._ST_gdalwarp($1, $3, $4, _srid, _scalex, _scaley, _gridx, _gridy, _skewx, _skewy, NULL, NULL);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rescale(rast raster, scalex double precision, scaley double precision, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125)
	RETURNS raster
	AS $$ SELECT  @extschema@._ST_GdalWarp($1, $4, $5, NULL, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rescale(rast raster, scalexy double precision, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125)
	RETURNS raster
	AS $$ SELECT  @extschema@._ST_GdalWarp($1, $3, $4, NULL, $2, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_reskew(rast raster, skewx double precision, skewy double precision, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_GdalWarp($1, $4, $5, NULL, 0, 0, NULL, NULL, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_reskew(rast raster, skewxy double precision, algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_GdalWarp($1, $3, $4, NULL, 0, 0, NULL, NULL, $2, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_snaptogrid(
	rast raster,
	gridx double precision, gridy double precision,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125,
	scalex double precision DEFAULT 0, scaley double precision DEFAULT 0
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_GdalWarp($1, $4, $5, NULL, $6, $7, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_snaptogrid(
	rast raster,
	gridx double precision, gridy double precision,
	scalex double precision, scaley double precision,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $6, $7, NULL, $4, $5, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_snaptogrid(
	rast raster,
	gridx double precision, gridy double precision,
	scalexy double precision,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $5, $6, NULL, $4, $4, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resize(
	rast raster,
	width text, height text,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$
	DECLARE
		i integer;

		wh text[2];

		whi integer[2];
		whd double precision[2];

		_width integer;
		_height integer;
	BEGIN
		wh[1] := trim(both from $2);
		wh[2] := trim(both from $3);

		-- see if width and height are percentages
		FOR i IN 1..2 LOOP
			IF position('%' in wh[i]) > 0 THEN
				BEGIN
					wh[i] := (regexp_matches(wh[i], E'^(\\d*.?\\d*)%{1}$'))[1];
					IF length(wh[i]) < 1 THEN
						RAISE invalid_parameter_value;
					END IF;

					whd[i] := wh[i]::double precision * 0.01;
				EXCEPTION WHEN OTHERS THEN -- TODO: WHEN invalid_parameter_value !
					RAISE EXCEPTION 'Invalid percentage value provided for width/height';
					RETURN NULL;
				END;
			ELSE
				BEGIN
					whi[i] := abs(wh[i]::integer);
				EXCEPTION WHEN OTHERS THEN -- TODO: only handle appropriate SQLSTATE
					RAISE EXCEPTION 'Non-integer value provided for width/height';
					RETURN NULL;
				END;
			END IF;
		END LOOP;

		IF whd[1] IS NOT NULL OR whd[2] IS NOT NULL THEN
			SELECT foo.width, foo.height INTO _width, _height FROM @extschema@.ST_Metadata($1) AS foo;

			IF whd[1] IS NOT NULL THEN
				whi[1] := round(_width::double precision * whd[1])::integer;
			END IF;

			IF whd[2] IS NOT NULL THEN
				whi[2] := round(_height::double precision * whd[2])::integer;
			END IF;

		END IF;

		-- should NEVER be here
		IF whi[1] IS NULL OR whi[2] IS NULL THEN
			RAISE EXCEPTION 'Unable to determine appropriate width or height';
			RETURN NULL;
		END IF;

		FOR i IN 1..2 LOOP
			IF whi[i] < 1 THEN
				whi[i] = 1;
			END IF;
		END LOOP;

		RETURN @extschema@._ST_gdalwarp(
			$1,
			$4, $5,
			NULL,
			NULL, NULL,
			NULL, NULL,
			NULL, NULL,
			whi[1], whi[2]
		);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resize(
	rast raster,
	width integer, height integer,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_gdalwarp($1, $4, $5, NULL, NULL, NULL, NULL, NULL, NULL, NULL, abs($2), abs($3)) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_resize(
	rast raster,
	percentwidth double precision, percentheight double precision,
	algorithm text DEFAULT 'NearestNeighbour', maxerr double precision DEFAULT 0.125
)
	RETURNS raster
	AS $$
	DECLARE
		_width integer;
		_height integer;
	BEGIN
		-- range check
		IF $2 <= 0. OR $2 > 1. OR $3 <= 0. OR $3 > 1. THEN
			RAISE EXCEPTION 'Percentages must be a value greater than zero and less than or equal to one, e.g. 0.5 for 50%%';
		END IF;

		SELECT width, height INTO _width, _height FROM @extschema@.ST_Metadata($1);

		_width := round(_width::double precision * $2)::integer;
		_height:= round(_height::double precision * $3)::integer;

		IF _width < 1 THEN
			_width := 1;
		END IF;
		IF _height < 1 THEN
			_height := 1;
		END IF;

		RETURN @extschema@._ST_gdalwarp(
			$1,
			$4, $5,
			NULL,
			NULL, NULL,
			NULL, NULL,
			NULL, NULL,
			_width, _height
		);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebraexpr(rast raster, band integer, pixeltype text,
        expression text, nodataval double precision DEFAULT NULL)
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_mapAlgebraExpr'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebraexpr(rast raster, pixeltype text, expression text,
        nodataval double precision DEFAULT NULL)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebraexpr($1, 1, $2, $3, $4) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, band integer,
        pixeltype text, onerastuserfunc regprocedure, variadic args text[])
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_mapAlgebraFct'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, band integer,
        pixeltype text, onerastuserfunc regprocedure)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, $2, $3, $4, NULL) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, band integer,
        onerastuserfunc regprocedure, variadic args text[])
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, $2, NULL, $3, VARIADIC $4) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, band integer,
        onerastuserfunc regprocedure)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, $2, NULL, $3, NULL) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, pixeltype text,
        onerastuserfunc regprocedure, variadic args text[])
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, 1, $2, $3, VARIADIC $4) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, pixeltype text,
        onerastuserfunc regprocedure)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, 1, $2, $3, NULL) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, onerastuserfunc regprocedure,
        variadic args text[])
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, 1, NULL, $2, VARIADIC $3) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(rast raster, onerastuserfunc regprocedure)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_mapalgebrafct($1, 1, NULL, $2, NULL) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebraexpr(
	rast1 raster, band1 integer,
	rast2 raster, band2 integer,
	expression text,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	nodata1expr text DEFAULT NULL, nodata2expr text DEFAULT NULL,
	nodatanodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_mapAlgebra2'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebraexpr(
	rast1 raster,
	rast2 raster,
	expression text,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	nodata1expr text DEFAULT NULL, nodata2expr text DEFAULT NULL,
	nodatanodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_mapalgebraexpr($1, 1, $2, 1, $3, $4, $5, $6, $7, $8) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(
	rast1 raster, band1 integer,
	rast2 raster, band2 integer,
	tworastuserfunc regprocedure,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_mapAlgebra2'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafct(
	rast1 raster,
	rast2 raster,
	tworastuserfunc regprocedure,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_mapalgebrafct($1, 1, $2, 1, $3, $4, $5, VARIADIC $6) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebrafctngb(
    rast raster,
    band integer,
    pixeltype text,
    ngbwidth integer,
    ngbheight integer,
    onerastngbuserfunc regprocedure,
    nodatamode text,
    variadic args text[]
)
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_mapAlgebraFctNgb'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_max4ma(matrix float[][], nodatamode text, variadic args text[])
    RETURNS float AS
    $$
    DECLARE
        _matrix float[][];
        max float;
    BEGIN
        _matrix := matrix;
        max := '-Infinity'::float;
        FOR x in array_lower(_matrix, 1)..array_upper(_matrix, 1) LOOP
            FOR y in array_lower(_matrix, 2)..array_upper(_matrix, 2) LOOP
                IF _matrix[x][y] IS NULL THEN
                    IF NOT nodatamode = 'ignore' THEN
                        _matrix[x][y] := nodatamode::float;
                    END IF;
                END IF;
                IF max < _matrix[x][y] THEN
                    max := _matrix[x][y];
                END IF;
            END LOOP;
        END LOOP;
        RETURN max;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_min4ma(matrix float[][], nodatamode text, variadic args text[])
    RETURNS float AS
    $$
    DECLARE
        _matrix float[][];
        min float;
    BEGIN
        _matrix := matrix;
        min := 'Infinity'::float;
        FOR x in array_lower(_matrix, 1)..array_upper(_matrix, 1) LOOP
            FOR y in array_lower(_matrix, 2)..array_upper(_matrix, 2) LOOP
                IF _matrix[x][y] IS NULL THEN
                    IF NOT nodatamode = 'ignore' THEN
                        _matrix[x][y] := nodatamode::float;
                    END IF;
                END IF;
                IF min > _matrix[x][y] THEN
                    min := _matrix[x][y];
                END IF;
            END LOOP;
        END LOOP;
        RETURN min;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_sum4ma(matrix float[][], nodatamode text, variadic args text[])
    RETURNS float AS
    $$
    DECLARE
        _matrix float[][];
        sum float;
    BEGIN
        _matrix := matrix;
        sum := 0;
        FOR x in array_lower(matrix, 1)..array_upper(matrix, 1) LOOP
            FOR y in array_lower(matrix, 2)..array_upper(matrix, 2) LOOP
                IF _matrix[x][y] IS NULL THEN
                    IF nodatamode = 'ignore' THEN
                        _matrix[x][y] := 0;
                    ELSE
                        _matrix[x][y] := nodatamode::float;
                    END IF;
                END IF;
                sum := sum + _matrix[x][y];
            END LOOP;
        END LOOP;
        RETURN sum;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mean4ma(matrix float[][], nodatamode text, variadic args text[])
    RETURNS float AS
    $$
    DECLARE
        _matrix float[][];
        sum float;
        count float;
    BEGIN
        _matrix := matrix;
        sum := 0;
        count := 0;
        FOR x in array_lower(matrix, 1)..array_upper(matrix, 1) LOOP
            FOR y in array_lower(matrix, 2)..array_upper(matrix, 2) LOOP
                IF _matrix[x][y] IS NULL THEN
                    IF nodatamode = 'ignore' THEN
                        _matrix[x][y] := 0;
                    ELSE
                        _matrix[x][y] := nodatamode::float;
                        count := count + 1;
                    END IF;
                ELSE
                    count := count + 1;
                END IF;
                sum := sum + _matrix[x][y];
            END LOOP;
        END LOOP;
        IF count = 0 THEN
            RETURN NULL;
        END IF;
        RETURN sum / count;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_range4ma(matrix float[][], nodatamode text, variadic args text[])
    RETURNS float AS
    $$
    DECLARE
        _matrix float[][];
        min float;
        max float;
    BEGIN
        _matrix := matrix;
        min := 'Infinity'::float;
        max := '-Infinity'::float;
        FOR x in array_lower(matrix, 1)..array_upper(matrix, 1) LOOP
            FOR y in array_lower(matrix, 2)..array_upper(matrix, 2) LOOP
                IF _matrix[x][y] IS NULL THEN
                    IF NOT nodatamode = 'ignore' THEN
                        _matrix[x][y] := nodatamode::float;
                    END IF;
                END IF;
                IF min > _matrix[x][y] THEN
                    min = _matrix[x][y];
                END IF;
                IF max < _matrix[x][y] THEN
                    max = _matrix[x][y];
                END IF;
            END LOOP;
        END LOOP;
        IF max = '-Infinity'::float OR min = 'Infinity'::float THEN
            RETURN NULL;
        END IF;
        RETURN max - min;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_distinct4ma(matrix float[][], nodatamode TEXT, VARIADIC args TEXT[])
    RETURNS float AS
    $$ SELECT COUNT(DISTINCT unnest)::float FROM unnest($1) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_stddev4ma(matrix float[][], nodatamode TEXT, VARIADIC args TEXT[])
    RETURNS float AS
    $$ SELECT stddev(unnest) FROM unnest($1) $$
    LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_mapalgebra(
	rastbandargset rastbandarg[],
	callbackfunc regprocedure,
	pixeltype text DEFAULT NULL,
	distancex integer DEFAULT 0, distancey integer DEFAULT 0,
	extenttype text DEFAULT 'INTERSECTION', customextent raster DEFAULT NULL,
	mask double precision[][] DEFAULT NULL, weighted boolean DEFAULT NULL,
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_nMapAlgebra'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rastbandargset rastbandarg[],
	callbackfunc regprocedure,
	pixeltype text DEFAULT NULL,
	extenttype text DEFAULT 'INTERSECTION', customextent raster DEFAULT NULL,
	distancex integer DEFAULT 0, distancey integer DEFAULT 0,
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_MapAlgebra($1, $2, $3, $6, $7, $4, $5,NULL::double precision [],NULL::boolean, VARIADIC $8) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast raster, nband int[],
	callbackfunc regprocedure,
	pixeltype text DEFAULT NULL,
	extenttype text DEFAULT 'FIRST', customextent raster DEFAULT NULL,
	distancex integer DEFAULT 0, distancey integer DEFAULT 0,
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS $$
	DECLARE
		x int;
		argset rastbandarg[];
	BEGIN
		IF $2 IS NULL OR array_ndims($2) < 1 OR array_length($2, 1) < 1 THEN
			RAISE EXCEPTION 'Populated 1D array must be provided for nband';
			RETURN NULL;
		END IF;

		FOR x IN array_lower($2, 1)..array_upper($2, 1) LOOP
			IF $2[x] IS NULL THEN
				CONTINUE;
			END IF;

			argset := argset || ROW($1, $2[x])::rastbandarg;
		END LOOP;

		IF array_length(argset, 1) < 1 THEN
			RAISE EXCEPTION 'Populated 1D array must be provided for nband';
			RETURN NULL;
		END IF;

		RETURN @extschema@._ST_MapAlgebra(argset, $3, $4, $7, $8, $5, $6,NULL::double precision [],NULL::boolean, VARIADIC $9);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast raster, nband int,
	callbackfunc regprocedure,
	pixeltype text DEFAULT NULL,
	extenttype text DEFAULT 'FIRST', customextent raster DEFAULT NULL,
	distancex integer DEFAULT 0, distancey integer DEFAULT 0,
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_MapAlgebra(ARRAY[ROW($1, $2)]::rastbandarg[], $3, $4, $7, $8, $5, $6,NULL::double precision [],NULL::boolean, VARIADIC $9) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast1 raster, nband1 int,
	rast2 raster, nband2 int,
	callbackfunc regprocedure,
	pixeltype text DEFAULT NULL,
	extenttype text DEFAULT 'INTERSECTION', customextent raster DEFAULT NULL,
	distancex integer DEFAULT 0, distancey integer DEFAULT 0,
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_MapAlgebra(ARRAY[ROW($1, $2), ROW($3, $4)]::rastbandarg[], $5, $6, $9, $10, $7, $8,NULL::double precision [],NULL::boolean, VARIADIC $11) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast raster, nband int,
	callbackfunc regprocedure,
	mask double precision [][], weighted boolean,
	pixeltype text DEFAULT NULL,
	extenttype text DEFAULT 'INTERSECTION', customextent raster DEFAULT NULL,
	VARIADIC userargs text[] DEFAULT NULL
)
	RETURNS raster
	AS $$
	select @extschema@._ST_mapalgebra(ARRAY[ROW($1,$2)]::rastbandarg[],$3,$6,NULL::integer,NULL::integer,$7,$8,$4,$5,VARIADIC $9)
	$$ LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_mapalgebra(
	rastbandargset rastbandarg[],
	expression text,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	nodata1expr text DEFAULT NULL, nodata2expr text DEFAULT NULL,
	nodatanodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_nMapAlgebraExpr'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast raster, nband integer,
	pixeltype text,
	expression text, nodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_mapalgebra(ARRAY[ROW($1, $2)]::rastbandarg[], $4, $3, 'FIRST', $5::text) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast raster,
	pixeltype text,
	expression text, nodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_mapalgebra($1, 1, $2, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast1 raster, band1 integer,
	rast2 raster, band2 integer,
	expression text,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	nodata1expr text DEFAULT NULL, nodata2expr text DEFAULT NULL,
	nodatanodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_mapalgebra(ARRAY[ROW($1, $2), ROW($3, $4)]::rastbandarg[], $5, $6, $7, $8, $9, $10) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mapalgebra(
	rast1 raster,
	rast2 raster,
	expression text,
	pixeltype text DEFAULT NULL, extenttype text DEFAULT 'INTERSECTION',
	nodata1expr text DEFAULT NULL, nodata2expr text DEFAULT NULL,
	nodatanodataval double precision DEFAULT NULL
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_mapalgebra($1, 1, $2, 1, $3, $4, $5, $6, $7, $8) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_convertarray4ma(value double precision[][])
	RETURNS double precision[][][]
	AS $$
	DECLARE
		_value double precision[][][];
		x int;
		y int;
	BEGIN
		IF array_ndims(value) != 2 THEN
			RAISE EXCEPTION 'Function parameter must be a 2-dimension array';
		END IF;

		_value := array_fill(NULL::double precision, ARRAY[1, array_length(value, 1), array_length(value, 2)]::int[], ARRAY[1, array_lower(value, 1), array_lower(value, 2)]::int[]);

		-- row
		FOR y IN array_lower(value, 1)..array_upper(value, 1) LOOP
			-- column
			FOR x IN array_lower(value, 2)..array_upper(value, 2) LOOP
				_value[1][y][x] = value[y][x];
			END LOOP;
		END LOOP;

		RETURN _value;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_max4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		max double precision;
		x int;
		y int;
		z int;
		ndims int;
	BEGIN
		max := '-Infinity'::double precision;

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- raster
		FOR z IN array_lower(_value, 1)..array_upper(_value, 1) LOOP
			-- row
			FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
				-- column
				FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP
					IF _value[z][y][x] IS NULL THEN
						IF array_length(userargs, 1) > 0 THEN
							_value[z][y][x] = userargs[array_lower(userargs, 1)]::double precision;
						ELSE
							CONTINUE;
						END IF;
					END IF;

					IF _value[z][y][x] > max THEN
						max := _value[z][y][x];
					END IF;
				END LOOP;
			END LOOP;
		END LOOP;

		IF max = '-Infinity'::double precision THEN
			RETURN NULL;
		END IF;

		RETURN max;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_min4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		min double precision;
		x int;
		y int;
		z int;
		ndims int;
	BEGIN
		min := 'Infinity'::double precision;

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- raster
		FOR z IN array_lower(_value, 1)..array_upper(_value, 1) LOOP
			-- row
			FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
				-- column
				FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP
					IF _value[z][y][x] IS NULL THEN
						IF array_length(userargs, 1) > 0 THEN
							_value[z][y][x] = userargs[array_lower(userargs, 1)]::double precision;
						ELSE
							CONTINUE;
						END IF;
					END IF;

					IF _value[z][y][x] < min THEN
						min := _value[z][y][x];
					END IF;
				END LOOP;
			END LOOP;
		END LOOP;

		IF min = 'Infinity'::double precision THEN
			RETURN NULL;
		END IF;

		RETURN min;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_sum4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		sum double precision;
		x int;
		y int;
		z int;
		ndims int;
	BEGIN
		sum := 0;

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- raster
		FOR z IN array_lower(_value, 1)..array_upper(_value, 1) LOOP
			-- row
			FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
				-- column
				FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP
					IF _value[z][y][x] IS NULL THEN
						IF array_length(userargs, 1) > 0 THEN
							_value[z][y][x] = userargs[array_lower(userargs, 1)]::double precision;
						ELSE
							CONTINUE;
						END IF;
					END IF;

					sum := sum + _value[z][y][x];
				END LOOP;
			END LOOP;
		END LOOP;

		RETURN sum;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mean4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		sum double precision;
		count int;
		x int;
		y int;
		z int;
		ndims int;
	BEGIN
		sum := 0;
		count := 0;

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- raster
		FOR z IN array_lower(_value, 1)..array_upper(_value, 1) LOOP
			-- row
			FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
				-- column
				FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP
					IF _value[z][y][x] IS NULL THEN
						IF array_length(userargs, 1) > 0 THEN
							_value[z][y][x] = userargs[array_lower(userargs, 1)]::double precision;
						ELSE
							CONTINUE;
						END IF;
					END IF;

					sum := sum + _value[z][y][x];
					count := count + 1;
				END LOOP;
			END LOOP;
		END LOOP;

		IF count < 1 THEN
			RETURN NULL;
		END IF;

		RETURN sum / count::double precision;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_range4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		min double precision;
		max double precision;
		x int;
		y int;
		z int;
		ndims int;
	BEGIN
		min := 'Infinity'::double precision;
		max := '-Infinity'::double precision;

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- raster
		FOR z IN array_lower(_value, 1)..array_upper(_value, 1) LOOP
			-- row
			FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
				-- column
				FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP
					IF _value[z][y][x] IS NULL THEN
						IF array_length(userargs, 1) > 0 THEN
							_value[z][y][x] = userargs[array_lower(userargs, 1)]::double precision;
						ELSE
							CONTINUE;
						END IF;
					END IF;

					IF _value[z][y][x] < min THEN
						min := _value[z][y][x];
					END IF;
					IF _value[z][y][x] > max THEN
						max := _value[z][y][x];
					END IF;
				END LOOP;
			END LOOP;
		END LOOP;

		IF max = '-Infinity'::double precision OR min = 'Infinity'::double precision THEN
			RETURN NULL;
		END IF;

		RETURN max - min;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_distinct4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$ SELECT COUNT(DISTINCT unnest)::double precision FROM unnest($1) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_stddev4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$ SELECT stddev(unnest) FROM unnest($1) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_invdistweight4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		ndims int;

		k double precision DEFAULT 1.;
		_k double precision DEFAULT 1.;
		z double precision[];
		d double precision[];
		_d double precision;
		z0 double precision;

		_z integer;
		x integer;
		y integer;

		cx integer;
		cy integer;
		cv double precision;
		cw double precision DEFAULT NULL;

		w integer;
		h integer;
		max_dx double precision;
		max_dy double precision;
	BEGIN
--		RAISE NOTICE 'value = %', value;
--		RAISE NOTICE 'userargs = %', userargs;

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		_z := array_lower(_value, 1);

		-- width and height (0-based)
		h := array_upper(_value, 2) - array_lower(_value, 2);
		w := array_upper(_value, 3) - array_lower(_value, 3);

		-- max distance from center pixel
		max_dx := w / 2;
		max_dy := h / 2;
--		RAISE NOTICE 'max_dx, max_dy = %, %', max_dx, max_dy;

		-- correct width and height (1-based)
		w := w + 1;
		h := h + 1;
--		RAISE NOTICE 'w, h = %, %', w, h;

		-- width and height should be odd numbers
		IF w % 2. != 1 THEN
			RAISE EXCEPTION 'Width of neighborhood array does not permit for a center pixel';
		END IF;
		IF h % 2. != 1 THEN
			RAISE EXCEPTION 'Height of neighborhood array does not permit for a center pixel';
		END IF;

		-- center pixel's coordinates
		cy := max_dy + array_lower(_value, 2);
		cx := max_dx + array_lower(_value, 3);
--		RAISE NOTICE 'cx, cy = %, %', cx, cy;

		-- if userargs provided, only use the first two args
		IF userargs IS NOT NULL AND array_ndims(userargs) = 1 THEN
			-- first arg is power factor
			k := userargs[array_lower(userargs, 1)]::double precision;
			IF k IS NULL THEN
				k := _k;
			ELSEIF k < 0. THEN
				RAISE NOTICE 'Power factor (< 0) must be between 0 and 1.  Defaulting to 0';
				k := 0.;
			ELSEIF k > 1. THEN
				RAISE NOTICE 'Power factor (> 1) must be between 0 and 1.  Defaulting to 1';
				k := 1.;
			END IF;

			-- second arg is what to do if center pixel has a value
			-- this will be a weight to apply for the center pixel
			IF array_length(userargs, 1) > 1 THEN
				cw := abs(userargs[array_lower(userargs, 1) + 1]::double precision);
				IF cw IS NOT NULL THEN
					IF cw < 0. THEN
						RAISE NOTICE 'Weight (< 0) of center pixel value must be between 0 and 1.  Defaulting to 0';
						cw := 0.;
					ELSEIF cw > 1 THEN
						RAISE NOTICE 'Weight (> 1) of center pixel value must be between 0 and 1.  Defaulting to 1';
						cw := 1.;
					END IF;
				END IF;
			END IF;
		END IF;
--		RAISE NOTICE 'k = %', k;
		k = abs(k) * -1;

		-- center pixel value
		cv := _value[_z][cy][cx];

		-- check to see if center pixel has value
--		RAISE NOTICE 'cw = %', cw;
		IF cw IS NULL AND cv IS NOT NULL THEN
			RETURN cv;
		END IF;

		FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
			FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP
--				RAISE NOTICE 'value[%][%][%] = %', _z, y, x, _value[_z][y][x];

				-- skip NODATA values and center pixel
				IF _value[_z][y][x] IS NULL OR (x = cx AND y = cy) THEN
					CONTINUE;
				END IF;

				z := z || _value[_z][y][x];

				-- use pythagorean theorem
				_d := sqrt(power(cx - x, 2) + power(cy - y, 2));
--				RAISE NOTICE 'distance = %', _d;

				d := d || _d;
			END LOOP;
		END LOOP;
--		RAISE NOTICE 'z = %', z;
--		RAISE NOTICE 'd = %', d;

		-- neighborhood is NODATA
		IF z IS NULL OR array_length(z, 1) < 1 THEN
			-- center pixel has value
			IF cv IS NOT NULL THEN
				RETURN cv;
			ELSE
				RETURN NULL;
			END IF;
		END IF;

		z0 := 0;
		_d := 0;
		FOR x IN array_lower(z, 1)..array_upper(z, 1) LOOP
			d[x] := power(d[x], k);
			z[x] := z[x] * d[x];
			_d := _d + d[x];
			z0 := z0 + z[x];
		END LOOP;
		z0 := z0 / _d;
--		RAISE NOTICE 'z0 = %', z0;

		-- apply weight for center pixel if center pixel has value
		IF cv IS NOT NULL THEN
			z0 := (cw * cv) + ((1 - cw) * z0);
--			RAISE NOTICE '*z0 = %', z0;
		END IF;

		RETURN z0;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_mindist4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_value double precision[][][];
		ndims int;

		d double precision DEFAULT NULL;
		_d double precision;

		z integer;
		x integer;
		y integer;

		cx integer;
		cy integer;
		cv double precision;

		w integer;
		h integer;
		max_dx double precision;
		max_dy double precision;
	BEGIN

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		-- width and height (0-based)
		h := array_upper(_value, 2) - array_lower(_value, 2);
		w := array_upper(_value, 3) - array_lower(_value, 3);

		-- max distance from center pixel
		max_dx := w / 2;
		max_dy := h / 2;

		-- correct width and height (1-based)
		w := w + 1;
		h := h + 1;

		-- width and height should be odd numbers
		IF w % 2. != 1 THEN
			RAISE EXCEPTION 'Width of neighborhood array does not permit for a center pixel';
		END IF;
		IF h % 2. != 1 THEN
			RAISE EXCEPTION 'Height of neighborhood array does not permit for a center pixel';
		END IF;

		-- center pixel's coordinates
		cy := max_dy + array_lower(_value, 2);
		cx := max_dx + array_lower(_value, 3);

		-- center pixel value
		cv := _value[z][cy][cx];

		-- check to see if center pixel has value
		IF cv IS NOT NULL THEN
			RETURN 0.;
		END IF;

		FOR y IN array_lower(_value, 2)..array_upper(_value, 2) LOOP
			FOR x IN array_lower(_value, 3)..array_upper(_value, 3) LOOP

				-- skip NODATA values and center pixel
				IF _value[z][y][x] IS NULL OR (x = cx AND y = cy) THEN
					CONTINUE;
				END IF;

				-- use pythagorean theorem
				_d := sqrt(power(cx - x, 2) + power(cy - y, 2));
--				RAISE NOTICE 'distance = %', _d;

				IF d IS NULL OR _d < d THEN
					d := _d;
				END IF;
			END LOOP;
		END LOOP;
--		RAISE NOTICE 'd = %', d;

		RETURN d;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_slope4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		x integer;
		y integer;
		z integer;

		_pixwidth double precision;
		_pixheight double precision;
		_width double precision;
		_height double precision;
		_units text;
		_scale double precision;

		dz_dx double precision;
		dz_dy double precision;

		slope double precision;

		_value double precision[][][];
		ndims int;
	BEGIN

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		IF (
			array_lower(_value, 2) != 1 OR array_upper(_value, 2) != 3 OR
			array_lower(_value, 3) != 1 OR array_upper(_value, 3) != 3
		) THEN
			RAISE EXCEPTION 'First parameter of function must be a 1x3x3 array with each of the lower bounds starting from 1';
		END IF;

		IF array_length(userargs, 1) < 6 THEN
			RAISE EXCEPTION 'At least six elements must be provided for the third parameter';
		END IF;

		_pixwidth := userargs[1]::double precision;
		_pixheight := userargs[2]::double precision;
		_width := userargs[3]::double precision;
		_height := userargs[4]::double precision;
		_units := userargs[5];
		_scale := userargs[6]::double precision;

		
		-- check that center pixel isn't NODATA
		IF _value[z][2][2] IS NULL THEN
			RETURN NULL;
		-- substitute center pixel for any neighbor pixels that are NODATA
		ELSE
			FOR y IN 1..3 LOOP
				FOR x IN 1..3 LOOP
					IF _value[z][y][x] IS NULL THEN
						_value[z][y][x] = _value[z][2][2];
					END IF;
				END LOOP;
			END LOOP;
		END IF;

		dz_dy := ((_value[z][3][1] + _value[z][3][2] + _value[z][3][2] + _value[z][3][3]) -
			(_value[z][1][1] + _value[z][1][2] + _value[z][1][2] + _value[z][1][3])) / _pixheight;
		dz_dx := ((_value[z][1][3] + _value[z][2][3] + _value[z][2][3] + _value[z][3][3]) -
			(_value[z][1][1] + _value[z][2][1] + _value[z][2][1] + _value[z][3][1])) / _pixwidth;

		slope := sqrt(dz_dx * dz_dx + dz_dy * dz_dy) / (8 * _scale);

		-- output depends on user preference
		CASE substring(upper(trim(leading from _units)) for 3)
			-- percentages
			WHEN 'PER' THEN
				slope := 100.0 * slope;
			-- radians
			WHEN 'rad' THEN
				slope := atan(slope);
			-- degrees (default)
			ELSE
				slope := degrees(atan(slope));
		END CASE;

		RETURN slope;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_slope(
	rast raster, nband integer,
	customextent raster,
	pixeltype text DEFAULT '32BF', units text DEFAULT 'DEGREES',
	scale double precision DEFAULT 1.0,	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$
	DECLARE
		_rast @extschema@.raster;
		_nband integer;
		_pixtype text;
		_pixwidth double precision;
		_pixheight double precision;
		_width integer;
		_height integer;
		_customextent @extschema@.raster;
		_extenttype text;
	BEGIN
		_customextent := customextent;
		IF _customextent IS NULL THEN
			_extenttype := 'FIRST';
		ELSE
			_extenttype := 'CUSTOM';
		END IF;

		IF interpolate_nodata IS TRUE THEN
			_rast := @extschema@.ST_MapAlgebra(
				ARRAY[ROW(rast, nband)]::rastbandarg[],
				'@extschema@.st_invdistweight4ma(double precision[][][], integer[][], text[])'::regprocedure,
				pixeltype,
				'FIRST', NULL,
				1, 1
			);
			_nband := 1;
			_pixtype := NULL;
		ELSE
			_rast := rast;
			_nband := nband;
			_pixtype := pixeltype;
		END IF;

		-- get properties
		_pixwidth := @extschema@.ST_PixelWidth(_rast);
		_pixheight := @extschema@.ST_PixelHeight(_rast);
		SELECT width, height INTO _width, _height FROM @extschema@.ST_Metadata(_rast);

		RETURN @extschema@.ST_MapAlgebra(
			ARRAY[ROW(_rast, _nband)]::rastbandarg[],
			' @extschema@._ST_slope4ma(double precision[][][], integer[][], text[])'::regprocedure,
			_pixtype,
			_extenttype, _customextent,
			1, 1,
			_pixwidth::text, _pixheight::text,
			_width::text, _height::text,
			units::text, scale::text
		);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_slope(
	rast raster, nband integer DEFAULT 1,
	pixeltype text DEFAULT '32BF', units text DEFAULT 'DEGREES',
	scale double precision DEFAULT 1.0,	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_slope($1, $2, NULL::@extschema@.raster, $3, $4, $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_aspect4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		x integer;
		y integer;
		z integer;

		_width double precision;
		_height double precision;
		_units text;

		dz_dx double precision;
		dz_dy double precision;
		aspect double precision;
		halfpi double precision;

		_value double precision[][][];
		ndims int;
	BEGIN
		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		IF (
			array_lower(_value, 2) != 1 OR array_upper(_value, 2) != 3 OR
			array_lower(_value, 3) != 1 OR array_upper(_value, 3) != 3
		) THEN
			RAISE EXCEPTION 'First parameter of function must be a 1x3x3 array with each of the lower bounds starting from 1';
		END IF;

		IF array_length(userargs, 1) < 3 THEN
			RAISE EXCEPTION 'At least three elements must be provided for the third parameter';
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		_width := userargs[1]::double precision;
		_height := userargs[2]::double precision;
		_units := userargs[3];

		
		-- check that center pixel isn't NODATA
		IF _value[z][2][2] IS NULL THEN
			RETURN NULL;
		-- substitute center pixel for any neighbor pixels that are NODATA
		ELSE
			FOR y IN 1..3 LOOP
				FOR x IN 1..3 LOOP
					IF _value[z][y][x] IS NULL THEN
						_value[z][y][x] = _value[z][2][2];
					END IF;
				END LOOP;
			END LOOP;
		END IF;

		dz_dy := ((_value[z][3][1] + _value[z][3][2] + _value[z][3][2] + _value[z][3][3]) -
			(_value[z][1][1] + _value[z][1][2] + _value[z][1][2] + _value[z][1][3]));
		dz_dx := ((_value[z][1][3] + _value[z][2][3] + _value[z][2][3] + _value[z][3][3]) -
			(_value[z][1][1] + _value[z][2][1] + _value[z][2][1] + _value[z][3][1]));

		-- aspect is flat
		IF abs(dz_dx) = 0::double precision AND abs(dz_dy) = 0::double precision THEN
			RETURN -1;
		END IF;

		-- aspect is in radians
		aspect := atan2(dz_dy, -dz_dx);

		-- north = 0, pi/2 = east, 3pi/2 = west
		halfpi := pi() / 2.0;
		IF aspect > halfpi THEN
			aspect := (5.0 * halfpi) - aspect;
		ELSE
			aspect := halfpi - aspect;
		END IF;

		IF aspect = 2 * pi() THEN
			aspect := 0.;
		END IF;

		-- output depends on user preference
		CASE substring(upper(trim(leading from _units)) for 3)
			-- radians
			WHEN 'rad' THEN
				RETURN aspect;
			-- degrees (default)
			ELSE
				RETURN degrees(aspect);
		END CASE;

	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspect(
	rast raster, nband integer,
	customextent raster,
	pixeltype text DEFAULT '32BF', units text DEFAULT 'DEGREES',
	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$
	DECLARE
		_rast @extschema@.raster;
		_nband integer;
		_pixtype text;
		_width integer;
		_height integer;
		_customextent @extschema@.raster;
		_extenttype text;
	BEGIN
		_customextent := customextent;
		IF _customextent IS NULL THEN
			_extenttype := 'FIRST';
		ELSE
			_extenttype := 'CUSTOM';
		END IF;

		IF interpolate_nodata IS TRUE THEN
			_rast := @extschema@.ST_MapAlgebra(
				ARRAY[ROW(rast, nband)]::rastbandarg[],
				'@extschema@.st_invdistweight4ma(double precision[][][], integer[][], text[])'::regprocedure,
				pixeltype,
				'FIRST', NULL,
				1, 1
			);
			_nband := 1;
			_pixtype := NULL;
		ELSE
			_rast := rast;
			_nband := nband;
			_pixtype := pixeltype;
		END IF;

		-- get properties
		SELECT width, height INTO _width, _height FROM @extschema@.ST_Metadata(_rast);

		RETURN @extschema@.ST_MapAlgebra(
			ARRAY[ROW(_rast, _nband)]::rastbandarg[],
			' @extschema@._ST_aspect4ma(double precision[][][], integer[][], text[])'::regprocedure,
			_pixtype,
			_extenttype, _customextent,
			1, 1,
			_width::text, _height::text,
			units::text
		);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aspect(
	rast raster, nband integer DEFAULT 1,
	pixeltype text DEFAULT '32BF', units text DEFAULT 'DEGREES',
	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_aspect($1, $2, NULL::@extschema@.raster, $3, $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_hillshade4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		_pixwidth double precision;
		_pixheight double precision;
		_width double precision;
		_height double precision;
		_azimuth double precision;
		_altitude double precision;
		_bright double precision;
		_scale double precision;

		dz_dx double precision;
		dz_dy double precision;
		azimuth double precision;
		zenith double precision;
		slope double precision;
		aspect double precision;
		shade double precision;

		_value double precision[][][];
		ndims int;
		z int;
	BEGIN
		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		IF (
			array_lower(_value, 2) != 1 OR array_upper(_value, 2) != 3 OR
			array_lower(_value, 3) != 1 OR array_upper(_value, 3) != 3
		) THEN
			RAISE EXCEPTION 'First parameter of function must be a 1x3x3 array with each of the lower bounds starting from 1';
		END IF;

		IF array_length(userargs, 1) < 8 THEN
			RAISE EXCEPTION 'At least eight elements must be provided for the third parameter';
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		_pixwidth := userargs[1]::double precision;
		_pixheight := userargs[2]::double precision;
		_width := userargs[3]::double precision;
		_height := userargs[4]::double precision;
		_azimuth := userargs[5]::double precision;
		_altitude := userargs[6]::double precision;
		_bright := userargs[7]::double precision;
		_scale := userargs[8]::double precision;

		-- check that pixel is not edge pixel
		IF (pos[1][1] = 1 OR pos[1][2] = 1) OR (pos[1][1] = _width OR pos[1][2] = _height) THEN
			RETURN NULL;
		END IF;

		-- clamp azimuth
		IF _azimuth < 0. THEN
			RAISE NOTICE 'Clamping provided azimuth value % to 0', _azimuth;
			_azimuth := 0.;
		ELSEIF _azimuth >= 360. THEN
			RAISE NOTICE 'Converting provided azimuth value % to be between 0 and 360', _azimuth;
			_azimuth := _azimuth - (360. * floor(_azimuth / 360.));
		END IF;
		azimuth := 360. - _azimuth + 90.;
		IF azimuth >= 360. THEN
			azimuth := azimuth - 360.;
		END IF;
		azimuth := radians(azimuth);
		--RAISE NOTICE 'azimuth = %', azimuth;

		-- clamp altitude
		IF _altitude < 0. THEN
			RAISE NOTICE 'Clamping provided altitude value % to 0', _altitude;
			_altitude := 0.;
		ELSEIF _altitude > 90. THEN
			RAISE NOTICE 'Clamping provided altitude value % to 90', _altitude;
			_altitude := 90.;
		END IF;
		zenith := radians(90. - _altitude);
		--RAISE NOTICE 'zenith = %', zenith;

		-- clamp bright
		IF _bright < 0. THEN
			RAISE NOTICE 'Clamping provided bright value % to 0', _bright;
			_bright := 0.;
		ELSEIF _bright > 255. THEN
			RAISE NOTICE 'Clamping provided bright value % to 255', _bright;
			_bright := 255.;
		END IF;

		dz_dy := ((_value[z][3][1] + _value[z][3][2] + _value[z][3][2] + _value[z][3][3]) -
			(_value[z][1][1] + _value[z][1][2] + _value[z][1][2] + _value[z][1][3])) / (8 * _pixheight);
		dz_dx := ((_value[z][1][3] + _value[z][2][3] + _value[z][2][3] + _value[z][3][3]) -
			(_value[z][1][1] + _value[z][2][1] + _value[z][2][1] + _value[z][3][1])) / (8 * _pixwidth);

		slope := atan(sqrt(dz_dx * dz_dx + dz_dy * dz_dy) / _scale);

		IF dz_dx != 0. THEN
			aspect := atan2(dz_dy, -dz_dx);

			IF aspect < 0. THEN
				aspect := aspect + (2.0 * pi());
			END IF;
		ELSE
			IF dz_dy > 0. THEN
				aspect := pi() / 2.;
			ELSEIF dz_dy < 0. THEN
				aspect := (2. * pi()) - (pi() / 2.);
			-- set to pi as that is the expected PostgreSQL answer in Linux
			ELSE
				aspect := pi();
			END IF;
		END IF;

		shade := _bright * ((cos(zenith) * cos(slope)) + (sin(zenith) * sin(slope) * cos(azimuth - aspect)));

		IF shade < 0. THEN
			shade := 0;
		END IF;

		RETURN shade;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_hillshade(
	rast raster, nband integer,
	customextent raster,
	pixeltype text DEFAULT '32BF',
	azimuth double precision DEFAULT 315.0, altitude double precision DEFAULT 45.0,
	max_bright double precision DEFAULT 255.0, scale double precision DEFAULT 1.0,
	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS RASTER
	AS $$
	DECLARE
		_rast @extschema@.raster;
		_nband integer;
		_pixtype text;
		_pixwidth double precision;
		_pixheight double precision;
		_width integer;
		_height integer;
		_customextent @extschema@.raster;
		_extenttype text;
	BEGIN
		_customextent := customextent;
		IF _customextent IS NULL THEN
			_extenttype := 'FIRST';
		ELSE
			_extenttype := 'CUSTOM';
		END IF;

		IF interpolate_nodata IS TRUE THEN
			_rast := @extschema@.ST_MapAlgebra(
				ARRAY[ROW(rast, nband)]::rastbandarg[],
				'@extschema@.st_invdistweight4ma(double precision[][][], integer[][], text[])'::regprocedure,
				pixeltype,
				'FIRST', NULL,
				1, 1
			);
			_nband := 1;
			_pixtype := NULL;
		ELSE
			_rast := rast;
			_nband := nband;
			_pixtype := pixeltype;
		END IF;

		-- get properties
		_pixwidth := @extschema@.ST_PixelWidth(_rast);
		_pixheight := @extschema@.ST_PixelHeight(_rast);
		SELECT width, height, scalex INTO _width, _height FROM @extschema@.ST_Metadata(_rast);

		RETURN @extschema@.ST_MapAlgebra(
			ARRAY[ROW(_rast, _nband)]::rastbandarg[],
			' @extschema@._ST_hillshade4ma(double precision[][][], integer[][], text[])'::regprocedure,
			_pixtype,
			_extenttype, _customextent,
			1, 1,
			_pixwidth::text, _pixheight::text,
			_width::text, _height::text,
			$5::text, $6::text,
			$7::text, $8::text
		);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_hillshade(
	rast raster, nband integer DEFAULT 1,
	pixeltype text DEFAULT '32BF',
	azimuth double precision DEFAULT 315.0, altitude double precision DEFAULT 45.0,
	max_bright double precision DEFAULT 255.0, scale double precision DEFAULT 1.0,
	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS RASTER
	AS $$ SELECT @extschema@.ST_hillshade($1, $2, NULL::@extschema@.raster, $3, $4, $5, $6, $7, $8) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_tpi4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		x integer;
		y integer;
		z integer;

		Z1 double precision;
		Z2 double precision;
		Z3 double precision;
		Z4 double precision;
		Z5 double precision;
		Z6 double precision;
		Z7 double precision;
		Z8 double precision;
		Z9 double precision;

		tpi double precision;
		mean double precision;
		_value double precision[][][];
		ndims int;
	BEGIN
		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		IF (
			array_lower(_value, 2) != 1 OR array_upper(_value, 2) != 3 OR
			array_lower(_value, 3) != 1 OR array_upper(_value, 3) != 3
		) THEN
			RAISE EXCEPTION 'First parameter of function must be a 1x3x3 array with each of the lower bounds starting from 1';
		END IF;

		-- check that center pixel isn't NODATA
		IF _value[z][2][2] IS NULL THEN
			RETURN NULL;
		-- substitute center pixel for any neighbor pixels that are NODATA
		ELSE
			FOR y IN 1..3 LOOP
				FOR x IN 1..3 LOOP
					IF _value[z][y][x] IS NULL THEN
						_value[z][y][x] = _value[z][2][2];
					END IF;
				END LOOP;
			END LOOP;
		END IF;

		-------------------------------------------------
		--|   Z1= Z(-1,1) |  Z2= Z(0,1)	| Z3= Z(1,1)  |--
		-------------------------------------------------
		--|   Z4= Z(-1,0) |  Z5= Z(0,0) | Z6= Z(1,0)  |--
		-------------------------------------------------
		--|   Z7= Z(-1,-1)|  Z8= Z(0,-1)|  Z9= Z(1,-1)|--
		-------------------------------------------------

		Z1 := _value[z][1][1];
		Z2 := _value[z][2][1];
		Z3 := _value[z][3][1];
		Z4 := _value[z][1][2];
		Z5 := _value[z][2][2];
		Z6 := _value[z][3][2];
		Z7 := _value[z][1][3];
		Z8 := _value[z][2][3];
		Z9 := _value[z][3][3];

		mean := (Z1 + Z2 + Z3 + Z4 + Z6 + Z7 + Z8 + Z9)/8;
		tpi := Z5-mean;

		return tpi;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tpi(
	rast raster, nband integer,
	customextent raster,
	pixeltype text DEFAULT '32BF', interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$
	DECLARE
		_rast @extschema@.raster;
		_nband integer;
		_pixtype text;
		_pixwidth double precision;
		_pixheight double precision;
		_width integer;
		_height integer;
		_customextent @extschema@.raster;
		_extenttype text;
	BEGIN
		_customextent := customextent;
		IF _customextent IS NULL THEN
			_extenttype := 'FIRST';
		ELSE
			_extenttype := 'CUSTOM';
		END IF;

		IF interpolate_nodata IS TRUE THEN
			_rast := @extschema@.ST_MapAlgebra(
				ARRAY[ROW(rast, nband)]::rastbandarg[],
				'@extschema@.st_invdistweight4ma(double precision[][][], integer[][], text[])'::regprocedure,
				pixeltype,
				'FIRST', NULL,
				1, 1
			);
			_nband := 1;
			_pixtype := NULL;
		ELSE
			_rast := rast;
			_nband := nband;
			_pixtype := pixeltype;
		END IF;

		-- get properties
		_pixwidth := @extschema@.ST_PixelWidth(_rast);
		_pixheight := @extschema@.ST_PixelHeight(_rast);
		SELECT width, height INTO _width, _height FROM @extschema@.ST_Metadata(_rast);

		RETURN @extschema@.ST_MapAlgebra(
			ARRAY[ROW(_rast, _nband)]::rastbandarg[],
			' @extschema@._ST_tpi4ma(double precision[][][], integer[][], text[])'::regprocedure,
			_pixtype,
			_extenttype, _customextent,
			1, 1);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tpi(
	rast raster, nband integer DEFAULT 1,
	pixeltype text DEFAULT '32BF', interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS RASTER
	AS $$ SELECT @extschema@.ST_tpi($1, $2, NULL::@extschema@.raster, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_roughness4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		x integer;
		y integer;
		z integer;

		minimum double precision;
		maximum double precision;

		_value double precision[][][];
		ndims int;
	BEGIN

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		IF (
			array_lower(_value, 2) != 1 OR array_upper(_value, 2) != 3 OR
			array_lower(_value, 3) != 1 OR array_upper(_value, 3) != 3
		) THEN
			RAISE EXCEPTION 'First parameter of function must be a 1x3x3 array with each of the lower bounds starting from 1';
		END IF;

		-- check that center pixel isn't NODATA
		IF _value[z][2][2] IS NULL THEN
			RETURN NULL;
		-- substitute center pixel for any neighbor pixels that are NODATA
		ELSE
			FOR y IN 1..3 LOOP
				FOR x IN 1..3 LOOP
					IF _value[z][y][x] IS NULL THEN
						_value[z][y][x] = _value[z][2][2];
					END IF;
				END LOOP;
			END LOOP;
		END IF;

		minimum := _value[z][1][1];
		maximum := _value[z][1][1];

		FOR Y IN 1..3 LOOP
		    FOR X IN 1..3 LOOP
		    	 IF _value[z][y][x] < minimum THEN
			    minimum := _value[z][y][x];
			 ELSIF _value[z][y][x] > maximum THEN
			    maximum := _value[z][y][x];
			 END IF;
		    END LOOP;
		END LOOP;

		RETURN maximum - minimum;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_roughness(
	rast raster, nband integer,
	customextent raster,
	pixeltype text DEFAULT '32BF', interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$
	DECLARE
		_rast @extschema@.raster;
		_nband integer;
		_pixtype text;
		_pixwidth double precision;
		_pixheight double precision;
		_width integer;
		_height integer;
		_customextent @extschema@.raster;
		_extenttype text;
	BEGIN
		_customextent := customextent;
		IF _customextent IS NULL THEN
			_extenttype := 'FIRST';
		ELSE
			_extenttype := 'CUSTOM';
		END IF;

		IF interpolate_nodata IS TRUE THEN
			_rast := @extschema@.ST_MapAlgebra(
				ARRAY[ROW(rast, nband)]::rastbandarg[],
				'@extschema@.st_invdistweight4ma(double precision[][][], integer[][], text[])'::regprocedure,
				pixeltype,
				'FIRST', NULL,
				1, 1
			);
			_nband := 1;
			_pixtype := NULL;
		ELSE
			_rast := rast;
			_nband := nband;
			_pixtype := pixeltype;
		END IF;

		RETURN @extschema@.ST_MapAlgebra(
			ARRAY[ROW(_rast, _nband)]::rastbandarg[],
			' @extschema@._ST_roughness4ma(double precision[][][], integer[][], text[])'::regprocedure,
			_pixtype,
			_extenttype, _customextent,
			1, 1);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_roughness(
	rast raster, nband integer DEFAULT 1,
	pixeltype text DEFAULT '32BF', interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS RASTER
	AS $$ SELECT @extschema@.ST_roughness($1, $2, NULL::@extschema@.raster, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_tri4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		x integer;
		y integer;
		z integer;

		Z1 double precision;
		Z2 double precision;
		Z3 double precision;
		Z4 double precision;
		Z5 double precision;
		Z6 double precision;
		Z7 double precision;
		Z8 double precision;
		Z9 double precision;

		tri double precision;
		_value double precision[][][];
		ndims int;
	BEGIN
		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		-- only use the first raster passed to this function
		IF array_length(_value, 1) > 1 THEN
			RAISE NOTICE 'Only using the values from the first raster';
		END IF;
		z := array_lower(_value, 1);

		IF (
			array_lower(_value, 2) != 1 OR array_upper(_value, 2) != 3 OR
			array_lower(_value, 3) != 1 OR array_upper(_value, 3) != 3
		) THEN
			RAISE EXCEPTION 'First parameter of function must be a 1x3x3 array with each of the lower bounds starting from 1';
		END IF;

		-- check that center pixel isn't NODATA
		IF _value[z][2][2] IS NULL THEN
			RETURN NULL;
		-- substitute center pixel for any neighbor pixels that are NODATA
		ELSE
			FOR y IN 1..3 LOOP
				FOR x IN 1..3 LOOP
					IF _value[z][y][x] IS NULL THEN
						_value[z][y][x] = _value[z][2][2];
					END IF;
				END LOOP;
			END LOOP;
		END IF;

		-------------------------------------------------
		--|   Z1= Z(-1,1) |  Z2= Z(0,1)	| Z3= Z(1,1)  |--
		-------------------------------------------------
		--|   Z4= Z(-1,0) |  Z5= Z(0,0) | Z6= Z(1,0)  |--
		-------------------------------------------------
		--|   Z7= Z(-1,-1)|  Z8= Z(0,-1)|  Z9= Z(1,-1)|--
		-------------------------------------------------

		-- _scale width and height units / z units to make z units equal to height width units
		Z1 := _value[z][1][1];
		Z2 := _value[z][2][1];
		Z3 := _value[z][3][1];
		Z4 := _value[z][1][2];
		Z5 := _value[z][2][2];
		Z6 := _value[z][3][2];
		Z7 := _value[z][1][3];
		Z8 := _value[z][2][3];
		Z9 := _value[z][3][3];

		tri := ( abs(Z1 - Z5 ) + abs( Z2 - Z5 ) + abs( Z3 - Z5 ) + abs( Z4 - Z5 ) + abs( Z6 - Z5 ) + abs( Z7 - Z5 ) + abs( Z8 - Z5 ) + abs ( Z9 - Z5 )) / 8;

		return tri;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tri(
	rast raster, nband integer,
	customextent raster,
	pixeltype text DEFAULT '32BF',	interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$
	DECLARE
		_rast @extschema@.raster;
		_nband integer;
		_pixtype text;
		_pixwidth double precision;
		_pixheight double precision;
		_width integer;
		_height integer;
		_customextent @extschema@.raster;
		_extenttype text;
	BEGIN
		_customextent := customextent;
		IF _customextent IS NULL THEN
			_extenttype := 'FIRST';
		ELSE
			_extenttype := 'CUSTOM';
		END IF;

		IF interpolate_nodata IS TRUE THEN
			_rast := @extschema@.ST_MapAlgebra(
				ARRAY[ROW(rast, nband)]::rastbandarg[],
				'@extschema@.st_invdistweight4ma(double precision[][][], integer[][], text[])'::regprocedure,
				pixeltype,
				'FIRST', NULL,
				1, 1
			);
			_nband := 1;
			_pixtype := NULL;
		ELSE
			_rast := rast;
			_nband := nband;
			_pixtype := pixeltype;
		END IF;

		-- get properties
		_pixwidth := @extschema@.ST_PixelWidth(_rast);
		_pixheight := @extschema@.ST_PixelHeight(_rast);
		SELECT width, height INTO _width, _height FROM @extschema@.ST_Metadata(_rast);

		RETURN @extschema@.ST_MapAlgebra(
			ARRAY[ROW(_rast, _nband)]::rastbandarg[],
			' @extschema@._ST_tri4ma(double precision[][][], integer[][], text[])'::regprocedure,
			_pixtype,
			_extenttype, _customextent,
			1, 1);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tri(
	rast raster, nband integer DEFAULT 1,
	pixeltype text DEFAULT '32BF', interpolate_nodata boolean DEFAULT FALSE
)
	RETURNS RASTER
	AS $$ SELECT @extschema@.ST_tri($1, $2, NULL::@extschema@.raster, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_grayscale4ma(value double precision[][][], pos integer[][], VARIADIC userargs text[] DEFAULT NULL)
	RETURNS double precision
	AS $$
	DECLARE
		ndims integer;
		_value double precision[][][];

		red double precision;
		green double precision;
		blue double precision;

		gray double precision;
	BEGIN

		ndims := array_ndims(value);
		-- add a third dimension if 2-dimension
		IF ndims = 2 THEN
			_value := @extschema@._ST_convertarray4ma(value);
		ELSEIF ndims != 3 THEN
			RAISE EXCEPTION 'First parameter of function must be a 3-dimension array';
		ELSE
			_value := value;
		END IF;

		red := _value[1][1][1];
		green := _value[2][1][1];
		blue := _value[3][1][1];

		gray = round(0.2989 * red + 0.5870 * green + 0.1140 * blue);
		RETURN gray;

	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_grayscale(
	rastbandargset rastbandarg[],
	extenttype text DEFAULT 'INTERSECTION'
)
	RETURNS RASTER
	AS $$
	DECLARE

		_NBANDS integer DEFAULT 3;
		_NODATA integer DEFAULT 255;
		_PIXTYPE text DEFAULT '8BUI';

		_set rastbandarg[];

		nrast integer;
		idx integer;
		rast @extschema@.raster;
		nband integer;

		stats summarystats;
		nodata double precision;
		nodataval integer;
		reclassexpr text;

	BEGIN

		-- check for three rastbandarg
		nrast := array_length(rastbandargset, 1);
		IF nrast < _NBANDS THEN
			RAISE EXCEPTION '''rastbandargset'' must have three bands for red, green and blue';
		ELSIF nrast > _NBANDS THEN
			RAISE WARNING 'Only the first three elements of ''rastbandargset'' will be used';
			_set := rastbandargset[1:3];
		ELSE
			_set := rastbandargset;
		END IF;

		FOR idx IN 1.._NBANDS LOOP

			rast := _set[idx].rast;
			nband := _set[idx].nband;

			-- check that each raster has the specified band
			IF @extschema@.ST_HasNoBand(rast, nband) THEN

				RAISE EXCEPTION 'Band at index ''%'' not found for raster ''%''', nband, idx;

			-- check that each band is 8BUI. if not, reclassify to 8BUI
			ELSIF @extschema@.ST_BandPixelType(rast, nband) != _PIXTYPE THEN

				stats := @extschema@.ST_SummaryStats(rast, nband);
				nodata := @extschema@.ST_BandNoDataValue(rast, nband);

				IF nodata IS NOT NULL THEN
					nodataval := _NODATA;
					reclassexpr := concat(
						concat('[', nodata , '-', nodata, ']:', _NODATA, '-', _NODATA, ','),
						concat('[', stats.min , '-', stats.max , ']:0-', _NODATA - 1)
					);
				ELSE
					nodataval := NULL;
					reclassexpr := concat('[', stats.min , '-', stats.max , ']:0-', _NODATA);
				END IF;

				_set[idx] := ROW(
					@extschema@.ST_Reclass(
						rast,
						ROW(nband, reclassexpr, _PIXTYPE, nodataval)::reclassarg
					),
					nband
				)::rastbandarg;

			END IF;

		END LOOP;

		-- call map algebra with _st_grayscale4ma
		RETURN @extschema@.ST_MapAlgebra(
			_set,
			'@extschema@._ST_Grayscale4MA(double precision[][][], integer[][], text[])'::regprocedure,
			'8BUI',
			extenttype
		);

	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_grayscale(
	rast raster,
 	redband integer DEFAULT 1,
 	greenband integer DEFAULT 2,
 	blueband integer DEFAULT 3,
	extenttype text DEFAULT 'INTERSECTION'
)
	RETURNS RASTER
	AS $$
	DECLARE
	BEGIN

		RETURN @extschema@.ST_Grayscale(
			ARRAY[
				ROW(rast, redband)::rastbandarg,
				ROW(rast, greenband)::rastbandarg,
				ROW(rast, blueband)::rastbandarg
			]::rastbandarg[],
			extenttype
		);

	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_isempty(rast raster)
    RETURNS boolean
    AS '$libdir/postgis_raster-3', 'RASTER_isEmpty'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_hasnoband(rast raster, nband int DEFAULT 1)
    RETURNS boolean
    AS '$libdir/postgis_raster-3', 'RASTER_hasNoBand'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_bandnodatavalue(rast raster, band integer DEFAULT 1)
    RETURNS double precision
    AS '$libdir/postgis_raster-3','RASTER_getBandNoDataValue'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_bandisnodata(rast raster, band integer DEFAULT 1, forceChecking boolean DEFAULT FALSE)
    RETURNS boolean
    AS '$libdir/postgis_raster-3', 'RASTER_bandIsNoData'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_bandisnodata(rast raster, forceChecking boolean)
    RETURNS boolean
    AS $$ SELECT @extschema@.ST_bandisnodata($1, 1, $2) $$
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_bandpath(rast raster, band integer DEFAULT 1)
    RETURNS text
    AS '$libdir/postgis_raster-3','RASTER_getBandPath'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_BandPixelType(rast raster, band integer DEFAULT 1)
    RETURNS text
    AS '$libdir/postgis_raster-3','RASTER_getBandPixelTypeName'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_BandMetaData(
	rast raster,
	band int[])
	RETURNS TABLE(
		bandnum int,
		pixeltype text,
		nodatavalue double precision,
		isoutdb boolean,
		path text,
		outdbbandnum integer,
		filesize bigint,
		filetimestamp bigint
	)
	AS '$libdir/postgis_raster-3','RASTER_bandmetadata'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_BandMetaData(
	rast raster,
	band int DEFAULT 1)
	RETURNS TABLE (
		pixeltype text,
		nodatavalue double precision,
		isoutdb boolean,
		path text,
		outdbbandnum integer,
		filesize bigint,
		filetimestamp bigint
	)
	AS $$ SELECT pixeltype, nodatavalue, isoutdb, path, outdbbandnum, filesize, filetimestamp FROM @extschema@.ST_BandMetaData($1, ARRAY[$2]::int[]) LIMIT 1 $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_BandFileSize(rast raster, band integer DEFAULT 1)
    RETURNS bigint
    AS '$libdir/postgis_raster-3','RASTER_getBandFileSize'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION St_BandFileTimestamp(rast raster, band integer DEFAULT 1)
    RETURNS bigint
    AS '$libdir/postgis_raster-3','RASTER_getBandFileTimestamp'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_value(rast raster, band integer, x integer, y integer, exclude_nodata_value boolean DEFAULT TRUE)
    RETURNS float8
    AS '$libdir/postgis_raster-3','RASTER_getPixelValue'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_value(rast raster, band integer, pt geometry, exclude_nodata_value boolean DEFAULT TRUE, resample text DEFAULT 'nearest')
	RETURNS float8
	AS '$libdir/postgis_raster-3', 'RASTER_getPixelValueResample'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_value(rast raster, x integer, y integer, exclude_nodata_value boolean DEFAULT TRUE)
    RETURNS float8
    AS $$ SELECT st_value($1, 1::integer, $2, $3, $4) $$
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_value(rast raster, pt geometry, exclude_nodata_value boolean DEFAULT TRUE)
    RETURNS float8
    AS $$ SELECT @extschema@.ST_value($1, 1::integer, $2, $3, 'nearest'::text) $$
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setz(rast raster, geom geometry, resample text DEFAULT 'nearest', band integer default 1)
	RETURNS geometry
	AS '$libdir/postgis_raster-3', 'RASTER_getGeometryValues'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setm(rast raster, geom geometry, resample text DEFAULT 'nearest', band integer default 1)
	RETURNS geometry
	AS '$libdir/postgis_raster-3', 'RASTER_getGeometryValues'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelofvalue(
	rast raster,
	nband integer,
	search double precision[],
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS
	TABLE(
		val double precision,
		x integer,
		y integer
	)
	AS '$libdir/postgis_raster-3', 'RASTER_pixelOfValue'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_PixelofValue(
	rast raster,
	search double precision[],
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE (
		val double precision,
		x integer,
		y integer
	)
	AS $$ SELECT val, x, y FROM @extschema@.ST_PixelOfValue($1, 1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelofvalue(
	rast raster,
	nband integer,
	search double precision,
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE (
		x integer,
		y integer
	)
	AS $$ SELECT x, y FROM @extschema@.ST_PixelofValue($1, $2, ARRAY[$3], $4) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelofvalue(
	rast raster,
	search double precision,
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE (
		x integer,
		y integer
	)
	AS $$ SELECT x, y FROM @extschema@.ST_PixelOfValue($1, 1, ARRAY[$2], $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_georeference(rast raster, format text DEFAULT 'GDAL')
    RETURNS text AS
    $$
    DECLARE
				scale_x numeric;
				scale_y numeric;
				skew_x numeric;
				skew_y numeric;
				ul_x numeric;
				ul_y numeric;

        result text;
    BEGIN
			SELECT scalex::numeric, scaley::numeric, skewx::numeric, skewy::numeric, upperleftx::numeric, upperlefty::numeric
				INTO scale_x, scale_y, skew_x, skew_y, ul_x, ul_y FROM @extschema@.ST_Metadata(rast);

						-- scale x
            result := trunc(scale_x, 10) || E'\n';

						-- skew y
            result := result || trunc(skew_y, 10) || E'\n';

						-- skew x
            result := result || trunc(skew_x, 10) || E'\n';

						-- scale y
            result := result || trunc(scale_y, 10) || E'\n';

        IF format = 'ESRI' THEN
						-- upper left x
            result := result || trunc((ul_x + scale_x * 0.5), 10) || E'\n';

						-- upper left y
            result = result || trunc((ul_y + scale_y * 0.5), 10) || E'\n';
        ELSE -- IF format = 'GDAL' THEN
						-- upper left x
            result := result || trunc(ul_x, 10) || E'\n';

						-- upper left y
            result := result || trunc(ul_y, 10) || E'\n';
        END IF;

        RETURN result;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE; -- WITH (isstrict);
CREATE OR REPLACE FUNCTION st_setscale(rast raster, scale float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setScale'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setscale(rast raster, scalex float8, scaley float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setScaleXY'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setskew(rast raster, skew float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setSkew'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setskew(rast raster, skewx float8, skewy float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setSkewXY'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setsrid(rast raster, srid integer)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setSRID'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setupperleft(rast raster, upperleftx float8, upperlefty float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setUpperLeftXY'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setrotation(rast raster, rotation float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setRotation'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setgeotransform(rast raster,
    imag double precision,
    jmag double precision,
    theta_i double precision,
    theta_ij double precision,
    xoffset double precision,
    yoffset double precision)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setGeotransform'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setgeoreference(rast raster, georef text, format text DEFAULT 'GDAL')
    RETURNS raster AS
    $$
    DECLARE
        params text[];
        rastout @extschema@.raster;
    BEGIN
        IF rast IS NULL THEN
            RAISE WARNING 'Cannot set georeferencing on a null raster in st_setgeoreference.';
            RETURN rastout;
        END IF;

        SELECT regexp_matches(georef,
            E'(-?\\d+(?:\\.\\d+)?)\\s(-?\\d+(?:\\.\\d+)?)\\s(-?\\d+(?:\\.\\d+)?)\\s' ||
            E'(-?\\d+(?:\\.\\d+)?)\\s(-?\\d+(?:\\.\\d+)?)\\s(-?\\d+(?:\\.\\d+)?)') INTO params;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'st_setgeoreference requires a string with 6 floating point values.';
        END IF;

        IF format = 'ESRI' THEN
            -- params array is now:
            -- {scalex, skewy, skewx, scaley, upperleftx, upperlefty}
            rastout := @extschema@.ST_setscale(rast, params[1]::float8, params[4]::float8);
            rastout := @extschema@.ST_setskew(rastout, params[3]::float8, params[2]::float8);
            rastout := @extschema@.ST_setupperleft(rastout,
                                   params[5]::float8 - (params[1]::float8 * 0.5),
                                   params[6]::float8 - (params[4]::float8 * 0.5));
        ELSE
            IF format != 'GDAL' THEN
                RAISE WARNING 'Format ''%'' is not recognized, defaulting to GDAL format.', format;
            END IF;
            -- params array is now:
            -- {scalex, skewy, skewx, scaley, upperleftx, upperlefty}

            rastout := @extschema@.ST_setscale(rast, params[1]::float8, params[4]::float8);
            rastout := @extschema@.ST_setskew( rastout, params[3]::float8, params[2]::float8);
            rastout := @extschema@.ST_setupperleft(rastout, params[5]::float8, params[6]::float8);
        END IF;
        RETURN rastout;
    END;
    $$
    LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE; -- WITH (isstrict);
CREATE OR REPLACE FUNCTION st_setgeoreference(
	rast raster,
	upperleftx double precision, upperlefty double precision,
	scalex double precision, scaley double precision,
	skewx double precision, skewy double precision
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_setgeoreference($1, array_to_string(ARRAY[$4, $7, $6, $5, $2, $3], ' ')) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_tile(
	rast raster,
	width integer, height integer,
	nband integer[] DEFAULT NULL,
	padwithnodata boolean DEFAULT FALSE, nodataval double precision DEFAULT NULL
)
	RETURNS SETOF raster
	AS '$libdir/postgis_raster-3','RASTER_tile'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tile(
	rast raster, nband integer[],
	width integer, height integer,
	padwithnodata boolean DEFAULT FALSE, nodataval double precision DEFAULT NULL
)
	RETURNS SETOF raster
	AS $$ SELECT @extschema@._ST_tile($1, $3, $4, $2, $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tile(
	rast raster, nband integer,
	width integer, height integer,
	padwithnodata boolean DEFAULT FALSE, nodataval double precision DEFAULT NULL
)
	RETURNS SETOF raster
	AS $$ SELECT @extschema@._ST_tile($1, $3, $4, ARRAY[$2]::integer[], $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_tile(
	rast raster,
	width integer, height integer,
	padwithnodata boolean DEFAULT FALSE, nodataval double precision DEFAULT NULL
)
	RETURNS SETOF raster
	AS $$ SELECT @extschema@._ST_tile($1, $2, $3, NULL::integer[], $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setbandnodatavalue(rast raster, band integer, nodatavalue float8, forceChecking boolean DEFAULT FALSE)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setBandNoDataValue'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setbandnodatavalue(rast raster, nodatavalue float8)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_setbandnodatavalue($1, 1, $2, FALSE) $$
    LANGUAGE 'sql';
CREATE OR REPLACE FUNCTION st_setbandisnodata(rast raster, band integer DEFAULT 1)
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_setBandIsNoData'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setbandpath(rast raster, band integer, outdbpath text, outdbindex integer, force boolean DEFAULT FALSE)
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_setBandPath'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_setbandindex(rast raster, band integer, outdbindex integer, force boolean DEFAULT FALSE)
    RETURNS raster
		AS $$ SELECT @extschema@.ST_SetBandPath($1, $2, NULL, $3, $4) $$
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _ST_SetValues(
	rast raster, nband integer,
	x integer, y integer,
	newvalueset double precision[][],
	noset boolean[][] DEFAULT NULL,
	hasnosetvalue boolean DEFAULT FALSE,
	nosetvalue double precision DEFAULT NULL,
	keepnodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_setPixelValuesArray'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValues(
	rast raster, nband integer,
	x integer, y integer,
	newvalueset double precision[][],
	noset boolean[][] DEFAULT NULL,
	keepnodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_setvalues($1, $2, $3, $4, $5, $6, FALSE, NULL, $7) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValues(
	rast raster, nband integer,
	x integer, y integer,
	newvalueset double precision[][],
	nosetvalue double precision,
	keepnodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS $$ SELECT @extschema@._ST_setvalues($1, $2, $3, $4, $5, NULL, TRUE, $6, $7) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValues(
	rast raster, nband integer,
	x integer, y integer,
	width integer, height integer,
	newvalue double precision,
	keepnodata boolean DEFAULT FALSE
)
	RETURNS raster AS
	$$
	BEGIN
		IF width <= 0 OR height <= 0 THEN
			RAISE EXCEPTION 'Values for width and height must be greater than zero';
			RETURN NULL;
		END IF;
		RETURN @extschema@._ST_setvalues($1, $2, $3, $4, array_fill($7, ARRAY[$6, $5]::int[]), NULL, FALSE, NULL, $8);
	END;
	$$
	LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValues(
	rast raster,
	x integer, y integer,
	width integer, height integer,
	newvalue double precision,
	keepnodata boolean DEFAULT FALSE
)
	RETURNS raster AS
	$$
	BEGIN
		IF width <= 0 OR height <= 0 THEN
			RAISE EXCEPTION 'Values for width and height must be greater than zero';
			RETURN NULL;
		END IF;
		RETURN @extschema@._ST_setvalues($1, 1, $2, $3, array_fill($6, ARRAY[$5, $4]::int[]), NULL, FALSE, NULL, $7);
	END;
	$$
	LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValues(
	rast raster, nband integer,
	geomvalset geomval[],
	keepnodata boolean DEFAULT FALSE
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_setPixelValuesGeomval'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValue(rast raster, band integer, x integer, y integer, newvalue float8)
    RETURNS raster
    AS '$libdir/postgis_raster-3','RASTER_setPixelValue'
    LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValue(rast raster, x integer, y integer, newvalue float8)
    RETURNS raster
    AS $$ SELECT @extschema@.ST_SetValue($1, 1, $2, $3, $4) $$
    LANGUAGE 'sql';
CREATE OR REPLACE FUNCTION ST_SetValue(
	rast raster, nband integer,
	geom geometry, newvalue double precision
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_setvalues($1, $2, ARRAY[ROW($3, $4)]::geomval[], FALSE) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_SetValue(
	rast raster,
	geom geometry, newvalue double precision
)
	RETURNS raster
	AS $$ SELECT @extschema@.ST_setvalues($1, 1, ARRAY[ROW($2, $3)]::geomval[], FALSE) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_dumpaspolygons(rast raster, band integer DEFAULT 1, exclude_nodata_value boolean DEFAULT TRUE)
	RETURNS SETOF geomval
	AS '$libdir/postgis_raster-3','RASTER_dumpAsPolygons'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_dumpvalues(
	rast raster, nband integer[] DEFAULT NULL, exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE(nband integer, valarray double precision[][])
	AS '$libdir/postgis_raster-3','RASTER_dumpValues'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_dumpvalues(rast raster, nband integer, exclude_nodata_value boolean DEFAULT TRUE)
	RETURNS double precision[][]
	AS $$ SELECT valarray FROM @extschema@.ST_dumpvalues($1, ARRAY[$2]::integer[], $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_polygon(rast raster, band integer DEFAULT 1)
	RETURNS geometry
	AS '$libdir/postgis_raster-3','RASTER_getPolygon'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_pixelaspolygons(
	rast raster,
	band integer DEFAULT 1,
	columnx integer DEFAULT NULL,
	rowy integer DEFAULT NULL,
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE(
		geom geometry,
		val double precision,
		x integer,
		y integer
	)
	AS '$libdir/postgis_raster-3', 'RASTER_getPixelPolygons'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelaspolygons(
	rast raster,
	band integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE (
		geom geometry,
		val double precision,
		x int,
		y int
	)
	AS $$ SELECT geom, val, x, y FROM @extschema@._ST_pixelaspolygons($1, $2, NULL, NULL, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelaspolygon(rast raster, x integer, y integer)
	RETURNS geometry
	AS $$ SELECT geom FROM @extschema@._ST_pixelaspolygons($1, NULL, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelaspoints(
	rast raster,
	band integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE (
		geom geometry,
		val double precision,
		x int,
		y int
	)
	AS $$ SELECT @extschema@.ST_PointN(  @extschema@.ST_ExteriorRing(geom), 1), val, x, y FROM @extschema@._ST_pixelaspolygons($1, $2, NULL, NULL, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelaspoint(rast raster, x integer, y integer)
	RETURNS geometry
	AS $$ SELECT ST_PointN(ST_ExteriorRing(geom), 1) FROM @extschema@._ST_pixelaspolygons($1, NULL, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_pixelascentroids(
	rast raster,
	band integer DEFAULT 1,
	columnx integer DEFAULT NULL,
	rowy integer DEFAULT NULL,
	exclude_nodata_value boolean DEFAULT TRUE
	)
	RETURNS TABLE(
		geom geometry,
		val double precision,
		x integer,
		y integer
	)
	AS '$libdir/postgis_raster-3', 'RASTER_getPixelCentroids'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelascentroids(
	rast raster,
	band integer DEFAULT 1,
	exclude_nodata_value boolean DEFAULT TRUE)
	RETURNS TABLE (
		geom geometry,
		val double precision,
		x int,
		y int
	)
	AS $$ SELECT geom, val, x, y FROM @extschema@._ST_pixelascentroids($1, $2, NULL, NULL, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_pixelascentroid(rast raster, x integer, y integer)
	RETURNS geometry
	AS $$ SELECT geom FROM @extschema@._ST_pixelascentroids($1, NULL, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_worldtorastercoord(
	rast raster,
	longitude double precision DEFAULT NULL, latitude double precision DEFAULT NULL,
	OUT columnx integer,
	OUT rowy integer)
	RETURNS record
	AS '$libdir/postgis_raster-3', 'RASTER_worldToRasterCoord'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoord(
	rast raster,
	longitude double precision, latitude double precision,
	OUT columnx integer,
	OUT rowy integer)
	RETURNS record
	AS $$ SELECT columnx, rowy FROM @extschema@._ST_worldtorastercoord($1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoord(
	rast raster, pt geometry,
	OUT columnx integer,
	OUT rowy integer)
	RETURNS record AS
	$$
	DECLARE
		rx integer;
		ry integer;
	BEGIN
		IF @extschema@.ST_geometrytype(pt) != 'ST_Point' THEN
			RAISE EXCEPTION 'Attempting to compute raster coordinate with a non-point geometry';
		END IF;
		IF @extschema@.ST_SRID(rast) != @extschema@.ST_SRID(pt) THEN
			RAISE EXCEPTION 'Raster and geometry do not have the same SRID';
		END IF;

		SELECT rc.columnx AS x, rc.rowy AS y INTO columnx, rowy FROM @extschema@._ST_worldtorastercoord($1, @extschema@.ST_x(pt), @extschema@.ST_y(pt)) AS rc;
		RETURN;
	END;
	$$
	LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoordx(rast raster, xw float8, yw float8)
	RETURNS int
	AS $$ SELECT columnx FROM @extschema@._ST_worldtorastercoord($1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoordx(rast raster, xw float8)
	RETURNS int
	AS $$ SELECT columnx FROM @extschema@._ST_worldtorastercoord($1, $2, NULL) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoordx(rast raster, pt geometry)
	RETURNS int AS
	$$
	DECLARE
		xr integer;
	BEGIN
		IF ( @extschema@.ST_geometrytype(pt) != 'ST_Point' ) THEN
			RAISE EXCEPTION 'Attempting to compute raster coordinate with a non-point geometry';
		END IF;
		IF @extschema@.ST_SRID(rast) != @extschema@.ST_SRID(pt) THEN
			RAISE EXCEPTION 'Raster and geometry do not have the same SRID';
		END IF;
		SELECT columnx INTO xr FROM @extschema@._ST_worldtorastercoord($1, @extschema@.ST_x(pt), @extschema@.ST_y(pt));
		RETURN xr;
	END;
	$$
	LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoordy(rast raster, xw float8, yw float8)
	RETURNS int
	AS $$ SELECT rowy FROM @extschema@._ST_worldtorastercoord($1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoordy(rast raster, yw float8)
	RETURNS int
	AS $$ SELECT rowy FROM @extschema@._ST_worldtorastercoord($1, NULL, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_worldtorastercoordy(rast raster, pt geometry)
	RETURNS int AS
	$$
	DECLARE
		yr integer;
	BEGIN
		IF ( st_geometrytype(pt) != 'ST_Point' ) THEN
			RAISE EXCEPTION 'Attempting to compute raster coordinate with a non-point geometry';
		END IF;
		IF ST_SRID(rast) != ST_SRID(pt) THEN
			RAISE EXCEPTION 'Raster and geometry do not have the same SRID';
		END IF;
		SELECT rowy INTO yr FROM @extschema@._ST_worldtorastercoord($1, st_x(pt), st_y(pt));
		RETURN yr;
	END;
	$$
	LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_rastertoworldcoord(
	rast raster,
	columnx integer DEFAULT NULL, rowy integer DEFAULT NULL,
	OUT longitude double precision,
	OUT latitude double precision
	) RETURNS record
	AS '$libdir/postgis_raster-3', 'RASTER_rasterToWorldCoord'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastertoworldcoord(
	rast raster,
	columnx integer, rowy integer,
	OUT	longitude double precision,
	OUT latitude double precision
	) RETURNS record
	AS $$ SELECT longitude, latitude FROM @extschema@._ST_rastertoworldcoord($1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastertoworldcoordx(rast raster, xr int, yr int)
	RETURNS float8
	AS $$ SELECT longitude FROM @extschema@._ST_rastertoworldcoord($1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastertoworldcoordx(rast raster, xr int)
	RETURNS float8
	AS $$ SELECT longitude FROM @extschema@._ST_rastertoworldcoord($1, $2, NULL) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastertoworldcoordy(rast raster, xr int, yr int)
	RETURNS float8
	AS $$ SELECT latitude FROM @extschema@._ST_rastertoworldcoord($1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastertoworldcoordy(rast raster, yr int)
	RETURNS float8
	AS $$ SELECT latitude FROM @extschema@._ST_rastertoworldcoord($1, NULL, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_minpossiblevalue(pixeltype text)
	RETURNS double precision
	AS '$libdir/postgis_raster-3', 'RASTER_minPossibleValue'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastfromwkb(bytea)
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_fromWKB'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_rastfromhexwkb(text)
    RETURNS raster
    AS '$libdir/postgis_raster-3', 'RASTER_fromHexWKB'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_aswkb(raster, outasin boolean DEFAULT FALSE)
    RETURNS bytea
    AS '$libdir/postgis_raster-3', 'RASTER_asWKB'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_asbinary(raster, outasin boolean DEFAULT FALSE)
    RETURNS bytea
		AS $$ SELECT @extschema@.ST_AsWKB($1, $2) $$
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_ashexwkb(raster, outasin boolean DEFAULT FALSE)
    RETURNS text
    AS '$libdir/postgis_raster-3', 'RASTER_asHexWKB'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION bytea(raster)
    RETURNS bytea
    AS '$libdir/postgis_raster-3', 'RASTER_to_bytea'
    LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP CAST IF EXISTS (raster AS box3d)');
DROP CAST IF EXISTS (raster AS box3d);
CREATE CAST (raster AS box3d)
    WITH FUNCTION box3d(raster) AS ASSIGNMENT;
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP CAST IF EXISTS (raster AS geometry)');
DROP CAST IF EXISTS (raster AS geometry);
CREATE CAST (raster AS geometry)
    WITH FUNCTION st_convexhull(raster) AS ASSIGNMENT;
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP CAST IF EXISTS (raster AS bytea)');
DROP CAST IF EXISTS (raster AS bytea);
CREATE CAST (raster AS bytea)
    WITH FUNCTION bytea(raster) AS ASSIGNMENT;
CREATE OR REPLACE FUNCTION raster_hash(raster)
	RETURNS integer
	AS 'hashvarlena'
	LANGUAGE 'internal' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_eq(raster, raster)
	RETURNS bool
	AS $$ SELECT @extschema@.raster_hash($1) = @extschema@.raster_hash($2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
-- Operator raster = raster -- LastUpdated: 201
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 201 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '=' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR = (
	LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_eq,
	COMMUTATOR = '=',
	RESTRICT = eqsel, JOIN = eqjoinsel
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator class hash_raster_ops -- LastUpdated: 201
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN

  IF 201 > version_from_num FROM _postgis_upgrade_info()
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$
    CREATE OPERATOR CLASS hash_raster_ops
	DEFAULT FOR TYPE raster USING hash AS
	OPERATOR	1	= ,
	FUNCTION	1	raster_hash (raster);
    $postgis_proc_upgrade_parsed_def$;
  END IF; -- version_from >= 201
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION raster_overleft(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry &< $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_overright(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry &> $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_left(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry << $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_right(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry >> $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_overabove(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry |&> $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_overbelow(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry &<| $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_above(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry |>> $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_below(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry <<| $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_same(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry ~= $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_contained(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry OPERATOR(@extschema@.@) $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_contain(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry ~ $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_overlap(raster, raster)
    RETURNS bool
    AS 'select $1::@extschema@.geometry OPERATOR(@extschema@.&&) $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_geometry_contain(raster, geometry)
    RETURNS bool
    AS 'select $1::@extschema@.geometry ~ $2'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_contained_by_geometry(raster, geometry)
    RETURNS bool
    AS 'select $1::@extschema@.geometry OPERATOR(@extschema@.@) $2'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION raster_geometry_overlap(raster, geometry)
    RETURNS bool
    AS 'select $1::@extschema@.geometry OPERATOR(@extschema@.&&) $2'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION geometry_raster_contain(geometry, raster)
    RETURNS bool
    AS 'select $1 OPERATOR(@extschema@.~) $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION geometry_contained_by_raster(geometry, raster)
    RETURNS bool
    AS 'select $1 OPERATOR(@extschema@.@) $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION geometry_raster_overlap(geometry, raster)
    RETURNS bool
    AS 'select $1 OPERATOR(@extschema@.&&) $2::@extschema@.geometry'
    LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
-- Operator raster << raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '<<' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR << (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_left,
    COMMUTATOR = '>>',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster &< raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '&<' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR &< (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_overleft,
    COMMUTATOR = '&>',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster <<| raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '<<|' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR <<| (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_below,
    COMMUTATOR = '|>>',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster &<| raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '&<|' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR &<| (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_overbelow,
    COMMUTATOR = '|&>',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster && raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '&&' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR && (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_overlap,
    COMMUTATOR = '&&',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster &> raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '&>' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR &> (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_overright,
    COMMUTATOR = '&<',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster >> raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '>>' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR >> (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_right,
    COMMUTATOR = '<<',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster |&> raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '|&>' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR |&> (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_overabove,
    COMMUTATOR = '&<|',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster |>> raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '|>>' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR |>> (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_above,
    COMMUTATOR = '<<|',
    RESTRICT = positionsel, JOIN = positionjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster ~= raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '~=' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR ~= (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_same,
    COMMUTATOR = '~=',
    RESTRICT = eqsel, JOIN = eqjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster @ raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '@' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR @ (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_contained,
    COMMUTATOR = '~',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster ~ raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '~' AND
            tl.typname = 'raster' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR ~ (
    LEFTARG = raster, RIGHTARG = raster, PROCEDURE = raster_contain,
    COMMUTATOR = '@',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster ~ geometry -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '~' AND
            tl.typname = 'raster' AND
            tr.typname = 'geometry'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR ~ (
    LEFTARG = raster, RIGHTARG = geometry, PROCEDURE = raster_geometry_contain,
    -- COMMUTATOR = '@', -- see http://trac.osgeo.org/postgis/ticket/2532
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster @ geometry -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '@' AND
            tl.typname = 'raster' AND
            tr.typname = 'geometry'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR @ (
    LEFTARG = raster, RIGHTARG = geometry, PROCEDURE = raster_contained_by_geometry,
    COMMUTATOR = '~',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator raster && geometry -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '&&' AND
            tl.typname = 'raster' AND
            tr.typname = 'geometry'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR && (
    LEFTARG = raster, RIGHTARG = geometry, PROCEDURE = raster_geometry_overlap,
    COMMUTATOR = '&&',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator geometry ~ raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '~' AND
            tl.typname = 'geometry' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR ~ (
    LEFTARG = geometry, RIGHTARG = raster, PROCEDURE = geometry_raster_contain,
    -- COMMUTATOR = '@', -- see http://trac.osgeo.org/postgis/ticket/2532
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator geometry @ raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '@' AND
            tl.typname = 'geometry' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR @ (
    LEFTARG = geometry, RIGHTARG = raster, PROCEDURE = geometry_contained_by_raster,
    COMMUTATOR = '~',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
-- Operator geometry && raster -- LastUpdated: 200
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  --IF 200 > version_from_num FROM _postgis_upgrade_info()
    --We trust presence of operator rather than version info
    IF NOT EXISTS (
        SELECT o.oprname
        FROM
            pg_catalog.pg_operator o,
            pg_catalog.pg_type tl,
            pg_catalog.pg_type tr
        WHERE
            o.oprleft = tl.oid AND
            o.oprright = tr.oid AND
            o.oprcode != 0 AND
            o.oprname = '&&' AND
            tl.typname = 'geometry' AND
            tr.typname = 'raster'
    )
    THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OPERATOR && (
    LEFTARG = geometry, RIGHTARG = raster, PROCEDURE = geometry_raster_overlap,
    COMMUTATOR = '&&',
    RESTRICT = contsel, JOIN = contjoinsel
    );
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION st_samealignment(rast1 raster, rast2 raster)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_sameAlignment'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_samealignment(
	ulx1 double precision, uly1 double precision, scalex1 double precision, scaley1 double precision, skewx1 double precision, skewy1 double precision,
	ulx2 double precision, uly2 double precision, scalex2 double precision, scaley2 double precision, skewx2 double precision, skewy2 double precision
)
	RETURNS boolean
	AS $$ SELECT st_samealignment(st_makeemptyraster(1, 1, $1, $2, $3, $4, $5, $6), st_makeemptyraster(1, 1, $7, $8, $9, $10, $11, $12)) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
-- Type agg_samealignment -- LastUpdated: 201
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 201 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE agg_samealignment AS (
	refraster raster,
	aligned boolean
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_samealignment_transfn(agg agg_samealignment, rast raster)
	RETURNS agg_samealignment AS $$
	DECLARE
		m record;
		aligned boolean;
	BEGIN
		IF agg IS NULL THEN
			agg.refraster := NULL;
			agg.aligned := NULL;
		END IF;

		IF rast IS NULL THEN
			agg.aligned := NULL;
		ELSE
			IF agg.refraster IS NULL THEN
				m := ST_Metadata(rast);
				agg.refraster := ST_MakeEmptyRaster(1, 1, m.upperleftx, m.upperlefty, m.scalex, m.scaley, m.skewx, m.skewy, m.srid);
				agg.aligned := TRUE;
			ELSIF agg.aligned IS TRUE THEN
				agg.aligned := ST_SameAlignment(agg.refraster, rast);
			END IF;
		END IF;
		RETURN agg;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _ST_samealignment_finalfn(agg agg_samealignment)
	RETURNS boolean
	AS $$ SELECT $1.aligned $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
-- Aggregate st_samealignment(raster) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_samealignment(raster) (
	SFUNC = _st_samealignment_transfn,
	STYPE = agg_samealignment,
	parallel = safe,
	FINALFUNC = _st_samealignment_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_samealignment(raster)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_samealignment(raster) (
	SFUNC = _st_samealignment_transfn,
	STYPE = agg_samealignment,
	parallel = safe,
	FINALFUNC = _st_samealignment_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION st_notsamealignmentreason(rast1 raster, rast2 raster)
	RETURNS text
	AS '$libdir/postgis_raster-3', 'RASTER_notSameAlignmentReason'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_iscoveragetile(rast raster, coverage raster, tilewidth integer, tileheight integer)
	RETURNS boolean
	AS $$
	DECLARE
		_rastmeta record;
		_covmeta record;
		cr record;
		max integer[];
		tile integer[];
		edge integer[];
	BEGIN
		IF NOT ST_SameAlignment(rast, coverage) THEN
			RAISE NOTICE 'Raster and coverage are not aligned';
			RETURN FALSE;
		END IF;

		_rastmeta := ST_Metadata(rast);
		_covmeta := ST_Metadata(coverage);

		-- get coverage grid coordinates of upper-left of rast
		cr := ST_WorldToRasterCoord(coverage, _rastmeta.upperleftx, _rastmeta.upperlefty);

		-- rast is not part of coverage
		IF
			(cr.columnx < 1 OR cr.columnx > _covmeta.width) OR
			(cr.rowy < 1 OR cr.rowy > _covmeta.height)
		THEN
			RAISE NOTICE 'Raster is not in the coverage';
			RETURN FALSE;
		END IF;

		-- rast isn't on the coverage's grid
		IF
			((cr.columnx - 1) % tilewidth != 0) OR
			((cr.rowy - 1) % tileheight != 0)
		THEN
			RAISE NOTICE 'Raster is not aligned to tile grid of coverage';
			RETURN FALSE;
		END IF;

		-- max # of tiles on X and Y for coverage
		max[0] := ceil(_covmeta.width::double precision / tilewidth::double precision)::integer;
		max[1] := ceil(_covmeta.height::double precision / tileheight::double precision)::integer;

		-- tile # of rast in coverge
		tile[0] := (cr.columnx / tilewidth) + 1;
		tile[1] := (cr.rowy / tileheight) + 1;

		-- inner tile
		IF tile[0] < max[0] AND tile[1] < max[1] THEN
			IF
				(_rastmeta.width != tilewidth) OR
				(_rastmeta.height != tileheight)
			THEN
				RAISE NOTICE 'Raster width/height is invalid for interior tile of coverage';
				RETURN FALSE;
			ELSE
				RETURN TRUE;
			END IF;
		END IF;

		-- edge tile

		-- edge tile may have same size as inner tile
		IF
			(_rastmeta.width = tilewidth) AND
			(_rastmeta.height = tileheight)
		THEN
			RETURN TRUE;
		END IF;

		-- get edge tile width and height
		edge[0] := _covmeta.width - ((max[0] - 1) * tilewidth);
		edge[1] := _covmeta.height - ((max[1] - 1) * tileheight);

		-- edge tile not of expected tile size
		-- right and bottom
		IF tile[0] = max[0] AND tile[1] = max[1] THEN
			IF
				_rastmeta.width != edge[0] OR
				_rastmeta.height != edge[1]
			THEN
				RAISE NOTICE 'Raster width/height is invalid for right-most AND bottom-most tile of coverage';
				RETURN FALSE;
			END IF;
		ELSEIF tile[0] = max[0] THEN
			IF
				_rastmeta.width != edge[0] OR
				_rastmeta.height != tileheight
			THEN
				RAISE NOTICE 'Raster width/height is invalid for right-most tile of coverage';
				RETURN FALSE;
			END IF;
		ELSE
			IF
				_rastmeta.width != tilewidth OR
				_rastmeta.height != edge[1]
			THEN
				RAISE NOTICE 'Raster width/height is invalid for bottom-most tile of coverage';
				RETURN FALSE;
			END IF;
		END IF;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_intersects(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_intersects'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_intersects(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_intersects(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_intersects($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_intersects(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_intersects($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_intersects(geom geometry, rast raster, nband integer DEFAULT NULL)
	RETURNS boolean AS $$
	DECLARE
		hasnodata boolean := TRUE;
		_geom @extschema@.geometry;
	BEGIN
		IF @extschema@.ST_SRID(rast) != @extschema@.ST_SRID(geom) THEN
			RAISE EXCEPTION 'Raster and geometry do not have the same SRID';
		END IF;

		_geom := @extschema@.ST_ConvexHull(rast);
		IF nband IS NOT NULL THEN
			SELECT CASE WHEN bmd.nodatavalue IS NULL THEN FALSE ELSE NULL END INTO hasnodata FROM @extschema@.ST_BandMetaData(rast, nband) AS bmd;
		END IF;

		IF @extschema@.ST_Intersects(geom, _geom) IS NOT TRUE THEN
			RETURN FALSE;
		ELSEIF nband IS NULL OR hasnodata IS FALSE THEN
			RETURN TRUE;
		END IF;

		SELECT @extschema@.ST_Buffer(@extschema@.ST_Collect(t.geom), 0) INTO _geom FROM @extschema@.ST_PixelAsPolygons(rast, nband) AS t;
		RETURN @extschema@.ST_Intersects(geom, _geom);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_intersects(geom geometry, rast raster, nband integer DEFAULT NULL)
	RETURNS boolean AS
	$$ SELECT $1 OPERATOR(@extschema@.&&) $2::@extschema@.geometry AND @extschema@._st_intersects($1, $2, $3); $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_intersects(rast raster, geom geometry, nband integer DEFAULT NULL)
	RETURNS boolean
	AS $$ SELECT $1::@extschema@.geometry OPERATOR(@extschema@.&&) $2 AND @extschema@._st_intersects($2, $1, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_intersects(rast raster, nband integer, geom geometry)
	RETURNS boolean
	AS $$ SELECT $1::@extschema@.geometry OPERATOR(@extschema@.&&) $3 AND @extschema@._st_intersects($3, $1, $2) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_overlaps(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_overlaps'
	LANGUAGE 'c' IMMUTABLE STRICT
	COST 1000;
CREATE OR REPLACE FUNCTION st_overlaps(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_overlaps(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._ST_overlaps($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_overlaps(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_overlaps($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_touches(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_touches'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_touches(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_touches(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_touches($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_touches(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_touches($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_contains(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_contains'
	LANGUAGE 'c' IMMUTABLE STRICT
	COST 1000;
CREATE OR REPLACE FUNCTION st_contains(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_contains(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_contains($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_contains(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_contains($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_containsproperly(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_containsProperly'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_containsproperly(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_containsproperly(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_containsproperly($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_containsproperly(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_containsproperly($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_covers(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_covers'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_covers(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_covers(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_covers($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_covers(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_covers($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_coveredby(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_coveredby'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_coveredby(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_coveredby(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_coveredby($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_coveredby(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_coveredby($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _st_within(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT @extschema@._st_contains($3, $4, $1, $2) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_within(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT $1 OPERATOR(@extschema@.&&) $3 AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._st_within(@extschema@.st_convexhull($1), @extschema@.st_convexhull($3)) ELSE @extschema@._st_contains($3, $4, $1, $2) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_within(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_within($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _ST_DWithin(rast1 raster, nband1 integer, rast2 raster, nband2 integer, distance double precision)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_dwithin'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION ST_DWithin(rast1 raster, nband1 integer, rast2 raster, nband2 integer, distance double precision)
	RETURNS boolean
	AS $$ SELECT $1::@extschema@.geometry OPERATOR(@extschema@.&&) ST_Expand(ST_ConvexHull($3), $5) AND $3::geometry OPERATOR(@extschema@.&&) ST_Expand(ST_ConvexHull($1), $5) AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._ST_dwithin(st_convexhull($1), st_convexhull($3), $5) ELSE @extschema@._ST_dwithin($1, $2, $3, $4, $5) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION ST_DWithin(rast1 raster, rast2 raster, distance double precision)
	RETURNS boolean
	AS $$ SELECT @extschema@.st_dwithin($1, NULL::integer, $2, NULL::integer, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION _ST_DFullyWithin(rast1 raster, nband1 integer, rast2 raster, nband2 integer, distance double precision)
	RETURNS boolean
	AS '$libdir/postgis_raster-3', 'RASTER_dfullywithin'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION ST_DFullyWithin(rast1 raster, nband1 integer, rast2 raster, nband2 integer, distance double precision)
	RETURNS boolean
	AS $$ SELECT $1::@extschema@.geometry OPERATOR(@extschema@.&&) @extschema@.ST_Expand(@extschema@.ST_ConvexHull($3), $5) AND $3::geometry OPERATOR(@extschema@.&&) @extschema@.ST_Expand(@extschema@.ST_ConvexHull($1), $5) AND CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@._ST_DFullyWithin(@extschema@.ST_ConvexHull($1), @extschema@.ST_Convexhull($3), $5) ELSE @extschema@._ST_DFullyWithin($1, $2, $3, $4, $5) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION ST_DFullyWithin(rast1 raster, rast2 raster, distance double precision)
	RETURNS boolean
	AS $$ SELECT @extschema@.ST_DFullyWithin($1, NULL::integer, $2, NULL::integer, $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION st_disjoint(rast1 raster, nband1 integer, rast2 raster, nband2 integer)
	RETURNS boolean
	AS $$ SELECT CASE WHEN $2 IS NULL OR $4 IS NULL THEN @extschema@.ST_Disjoint(@extschema@.ST_ConvexHull($1), @extschema@.ST_ConvexHull($3)) ELSE NOT @extschema@._ST_intersects($1, $2, $3, $4) END $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION ST_Disjoint(rast1 raster, rast2 raster)
	RETURNS boolean
	AS $$ SELECT @extschema@.ST_Disjoint($1, NULL::integer, $2, NULL::integer) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE
	COST 1000;
CREATE OR REPLACE FUNCTION ST_Intersection(geomin geometry, rast raster, band integer DEFAULT 1)
	RETURNS SETOF geomval AS $$
	DECLARE
		intersects boolean := FALSE; same_srid boolean := FALSE;
	BEGIN
		same_srid :=  (@extschema@.ST_SRID(geomin) = @extschema@.ST_SRID(rast));
		IF NOT same_srid THEN
			RAISE EXCEPTION 'SRIDS of geometry: % and raster: % are not the same',
				@extschema@.ST_SRID(geomin), @extschema@.ST_SRID(rast)
				USING HINT = 'Verify using ST_SRID function';
		END IF;
		intersects :=  @extschema@.ST_Intersects(geomin, rast, band);
		IF intersects THEN
			-- Return the intersections of the geometry with the vectorized parts of
			-- the raster and the values associated with those parts, if really their
			-- intersection is not empty.
			RETURN QUERY
				SELECT
					intgeom,
					val
				FROM (
					SELECT
						@extschema@.ST_Intersection((gv).geom, geomin) AS intgeom,
						(gv).val
					FROM @extschema@.ST_DumpAsPolygons(rast, band) gv
					WHERE @extschema@.ST_Intersects((gv).geom, geomin)
				) foo
				WHERE NOT @extschema@.ST_IsEmpty(intgeom);
		ELSE
			-- If the geometry does not intersect with the raster, return an empty
			-- geometry and a null value
			RETURN QUERY
				SELECT
					emptygeom,
					NULL::float8
				FROM ST_GeomCollFromText('GEOMETRYCOLLECTION EMPTY', ST_SRID($1)) emptygeom;
		END IF;
	END;
	$$
	LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(rast raster, band integer, geomin geometry)
	RETURNS SETOF geomval AS
	$$ SELECT @extschema@.ST_Intersection($3, $1, $2) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_Intersection(rast raster, geomin geometry)
	RETURNS SETOF geomval AS
	$$ SELECT @extschema@.ST_Intersection($2, $1, 1) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION ST_Intersection(
	rast1 raster, band1 int,
	rast2 raster, band2 int,
	returnband text DEFAULT 'BOTH',
	nodataval double precision[] DEFAULT NULL
)
	RETURNS raster
	AS $$
	DECLARE
		rtn @extschema@.raster;
		_returnband text;
		newnodata1 float8;
		newnodata2 float8;
	BEGIN
		IF ST_SRID(rast1) != ST_SRID(rast2) THEN
			RAISE EXCEPTION 'The two rasters do not have the same SRID';
		END IF;

		newnodata1 := coalesce(nodataval[1], ST_BandNodataValue(rast1, band1), ST_MinPossibleValue(@extschema@.ST_BandPixelType(rast1, band1)));
		newnodata2 := coalesce(nodataval[2], ST_BandNodataValue(rast2, band2), ST_MinPossibleValue(@extschema@.ST_BandPixelType(rast2, band2)));

		_returnband := upper(returnband);

		rtn := NULL;
		CASE
			WHEN _returnband = 'BAND1' THEN
				rtn := @extschema@.ST_MapAlgebraExpr(rast1, band1, rast2, band2, '[rast1.val]', @extschema@.ST_BandPixelType(rast1, band1), 'INTERSECTION', newnodata1::text, newnodata1::text, newnodata1);
				rtn := @extschema@.ST_SetBandNodataValue(rtn, 1, newnodata1);
			WHEN _returnband = 'BAND2' THEN
				rtn := @extschema@.ST_MapAlgebraExpr(rast1, band1, rast2, band2, '[rast2.val]', @extschema@.ST_BandPixelType(rast2, band2), 'INTERSECTION', newnodata2::text, newnodata2::text, newnodata2);
				rtn := @extschema@.ST_SetBandNodataValue(rtn, 1, newnodata2);
			WHEN _returnband = 'BOTH' THEN
				rtn := @extschema@.ST_MapAlgebraExpr(rast1, band1, rast2, band2, '[rast1.val]', @extschema@.ST_BandPixelType(rast1, band1), 'INTERSECTION', newnodata1::text, newnodata1::text, newnodata1);
				rtn := ST_SetBandNodataValue(rtn, 1, newnodata1);
				rtn := ST_AddBand(rtn, ST_MapAlgebraExpr(rast1, band1, rast2, band2, '[rast2.val]', @extschema@.ST_BandPixelType(rast2, band2), 'INTERSECTION', newnodata2::text, newnodata2::text, newnodata2));
				rtn := ST_SetBandNodataValue(rtn, 2, newnodata2);
			ELSE
				RAISE EXCEPTION 'Unknown value provided for returnband: %', returnband;
				RETURN NULL;
		END CASE;

		RETURN rtn;
	END;
	$$ LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster, band1 int,
	rast2 raster, band2 int,
	returnband text,
	nodataval double precision
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, $2, $3, $4, $5, ARRAY[$6, $6]) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster, band1 int,
	rast2 raster, band2 int,
	nodataval double precision[]
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, $2, $3, $4, 'BOTH', $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster, band1 int,
	rast2 raster, band2 int,
	nodataval double precision
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, $2, $3, $4, 'BOTH', ARRAY[$5, $5]) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster,
	rast2 raster,
	returnband text DEFAULT 'BOTH',
	nodataval double precision[] DEFAULT NULL
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, 1, $2, 1, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster,
	rast2 raster,
	returnband text,
	nodataval double precision
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, 1, $2, 1, $3, ARRAY[$4, $4]) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster,
	rast2 raster,
	nodataval double precision[]
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, 1, $2, 1, 'BOTH', $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_intersection(
	rast1 raster,
	rast2 raster,
	nodataval double precision
)
	RETURNS raster AS
	$$ SELECT st_intersection($1, 1, $2, 1, 'BOTH', ARRAY[$3, $3]) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
-- Type unionarg -- LastUpdated: 201
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF 201 > version_from_num
     FROM _postgis_upgrade_info()
  THEN
      EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE TYPE unionarg AS (
	nband int,
	uniontype text
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_union_finalfn(internal)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_union_finalfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_union_transfn(internal, raster, unionarg[])
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_union_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_union(raster,unionarg[]) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_union(raster, unionarg[]) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_union(raster,unionarg[])';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_union(raster, unionarg[]) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_union_transfn(internal, raster, integer, text)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_union_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_union(raster,integer,text) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_union(raster, integer, text) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_union(raster,integer,text)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_union(raster, integer, text) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_union_transfn(internal, raster, integer)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_union_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_union(raster,integer) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_union(raster, integer) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_union(raster,integer)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_union(raster, integer) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_union_transfn(internal, raster)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_union_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_union(raster) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_union(raster) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_union(raster)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_union(raster) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_union_transfn(internal, raster, text)
	RETURNS internal
	AS '$libdir/postgis_raster-3', 'RASTER_union_transfn'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
-- Aggregate st_union(raster,text) -- LastUpdated: 204
DO LANGUAGE 'plpgsql'
$postgis_proc_upgrade$
BEGIN
  IF current_setting('server_version_num')::integer >= 120000
  THEN
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE OR REPLACE AGGREGATE st_union(raster, text) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  ELSIF 204 > version_from_num OR (
      204 = version_from_num AND version_from_isdev
    ) FROM _postgis_upgrade_info()
  THEN
    EXECUTE 'DROP AGGREGATE IF EXISTS st_union(raster,text)';
    EXECUTE $postgis_proc_upgrade_parsed_def$ CREATE AGGREGATE st_union(raster, text) (
	SFUNC = _st_union_transfn,
	STYPE = internal,
	parallel = safe,
	FINALFUNC = _st_union_finalfn
);
 $postgis_proc_upgrade_parsed_def$;
  END IF;
END
$postgis_proc_upgrade$;
CREATE OR REPLACE FUNCTION _st_clip(
	rast raster, nband integer[],
	geom geometry,
	nodataval double precision[] DEFAULT NULL, crop boolean DEFAULT TRUE
)
	RETURNS raster
	AS '$libdir/postgis_raster-3', 'RASTER_clip'
	LANGUAGE 'c' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_clip(
	rast raster, nband integer[],
	geom geometry,
	nodataval double precision[] DEFAULT NULL, crop boolean DEFAULT TRUE
)
	RETURNS raster
 	AS $$
	BEGIN
		-- short-cut if geometry's extent fully contains raster's extent
		IF (nodataval IS NULL OR array_length(nodataval, 1) < 1) AND @extschema@.ST_Contains(geom, @extschema@.ST_Envelope(rast)) THEN
			RETURN rast;
		END IF;

		RETURN @extschema@._ST_Clip($1, $2, $3, $4, $5);
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_clip(
	rast raster, nband integer,
	geom geometry,
	nodataval double precision, crop boolean DEFAULT TRUE
)
	RETURNS raster AS
	$$ SELECT @extschema@.ST_Clip($1, ARRAY[$2]::integer[], $3, ARRAY[$4]::double precision[], $5) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_clip(
	rast raster, nband integer,
	geom geometry,
	crop boolean
)
	RETURNS raster AS
	$$ SELECT @extschema@.ST_Clip($1, ARRAY[$2]::integer[], $3, null::double precision[], $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_clip(
	rast raster,
	geom geometry,
	nodataval double precision[] DEFAULT NULL, crop boolean DEFAULT TRUE
)
	RETURNS raster AS
	$$ SELECT @extschema@.ST_Clip($1, NULL, $2, $3, $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_clip(
	rast raster,
	geom geometry,
	nodataval double precision, crop boolean DEFAULT TRUE
)
	RETURNS raster AS
	$$ SELECT @extschema@.ST_Clip($1, NULL, $2, ARRAY[$3]::double precision[], $4) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_clip(
	rast raster,
	geom geometry,
	crop boolean
)
	RETURNS raster AS
	$$ SELECT @extschema@.ST_Clip($1, NULL, $2, null::double precision[], $3) $$
	LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_nearestvalue(
	rast raster, band integer,
	pt geometry,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision
	AS '$libdir/postgis_raster-3', 'RASTER_nearestValue'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_nearestvalue(
	rast raster,
	pt geometry,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision
	AS $$ SELECT st_nearestvalue($1, 1, $2, $3) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_nearestvalue(
	rast raster, band integer,
	columnx integer, rowy integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision
	AS $$ SELECT st_nearestvalue($1, $2, st_setsrid(st_makepoint(st_rastertoworldcoordx($1, $3, $4), st_rastertoworldcoordy($1, $3, $4)), st_srid($1)), $5) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_nearestvalue(
	rast raster,
	columnx integer, rowy integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision
	AS $$ SELECT st_nearestvalue($1, 1, st_setsrid(st_makepoint(st_rastertoworldcoordx($1, $2, $3), st_rastertoworldcoordy($1, $2, $3)), st_srid($1)), $4) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _st_neighborhood(
	rast raster, band integer,
	columnx integer, rowy integer,
	distancex integer, distancey integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision[][]
	AS '$libdir/postgis_raster-3', 'RASTER_neighborhood'
	LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_neighborhood(
	rast raster, band integer,
	columnx integer, rowy integer,
	distancex integer, distancey integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision[][]
	AS $$ SELECT @extschema@._ST_neighborhood($1, $2, $3, $4, $5, $6, $7) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_neighborhood(
	rast raster,
	columnx integer, rowy integer,
	distancex integer, distancey integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision[][]
	AS $$ SELECT @extschema@._ST_neighborhood($1, 1, $2, $3, $4, $5, $6) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_neighborhood(
	rast raster, band integer,
	pt geometry,
	distancex integer, distancey integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision[][]
	AS $$
	DECLARE
		wx double precision;
		wy double precision;
		rtn double precision[][];
	BEGIN
		IF (st_geometrytype($3) != 'ST_Point') THEN
			RAISE EXCEPTION 'Attempting to get the neighbor of a pixel with a non-point geometry';
		END IF;

		IF ST_SRID(rast) != ST_SRID(pt) THEN
			RAISE EXCEPTION 'Raster and geometry do not have the same SRID';
		END IF;

		wx := st_x($3);
		wy := st_y($3);

		SELECT @extschema@._ST_neighborhood(
			$1, $2,
			st_worldtorastercoordx(rast, wx, wy),
			st_worldtorastercoordy(rast, wx, wy),
			$4, $5,
			$6
		) INTO rtn;
		RETURN rtn;
	END;
	$$ LANGUAGE 'plpgsql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION st_neighborhood(
	rast raster,
	pt geometry,
	distancex integer, distancey integer,
	exclude_nodata_value boolean DEFAULT TRUE
)
	RETURNS double precision[][]
	AS $$ SELECT st_neighborhood($1, 1, $2, $3, $4, $5) $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _add_raster_constraint(cn name, sql text)
	RETURNS boolean AS $$
	BEGIN
		BEGIN
			EXECUTE sql;
		EXCEPTION
			WHEN duplicate_object THEN
				RAISE NOTICE 'The constraint "%" already exists.  To replace the existing constraint, delete the constraint and call ApplyRasterConstraints again', cn;
			WHEN OTHERS THEN
				RAISE NOTICE 'Unable to add constraint: %', cn;
				RAISE NOTICE 'SQL used for failed constraint: %', sql;
				RAISE NOTICE 'Returned error message: % (%)', SQLERRM, SQLSTATE;
				RETURN FALSE;
		END;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint(rastschema name, rasttable name, cn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		BEGIN
			EXECUTE 'ALTER TABLE '
				|| fqtn
				|| ' DROP CONSTRAINT '
				|| quote_ident(cn);
			RETURN TRUE;
		EXCEPTION
			WHEN undefined_object THEN
				RAISE NOTICE 'The constraint "%" does not exist.  Skipping', cn;
			WHEN OTHERS THEN
				RAISE NOTICE 'Unable to drop constraint "%": % (%)',
          cn, SQLERRM, SQLSTATE;
				RETURN FALSE;
		END;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_srid(rastschema name, rasttable name, rastcolumn name)
	RETURNS integer AS $$
	SELECT
		regexp_replace(
			split_part(s.consrc, ' = ', 2),
			'[\(\)]', '', 'g'
		)::integer
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
		    FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_srid(% = %';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_srid(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr int;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_srid_' || $3;

		sql := 'SELECT st_srid('
			|| quote_ident($3)
			|| ') FROM ' || fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1;';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the SRID of a sample raster: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK (st_srid('
			|| quote_ident($3)
			|| ') = ' || attr || ')';

		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_srid(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_srid_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_scale(rastschema name, rasttable name, rastcolumn name, axis char)
	RETURNS double precision AS $$
	WITH c AS (SELECT
		regexp_replace(
			replace(
				split_part(
					split_part(s.consrc, ' = ', 2),
					'::', 1
				),
				'round(', ''
			),
			'[ ''''\(\)]', '', 'g'
		)::text AS val
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
		    FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_scale' || $4 || '(% = %')
-- if it is a comma separated list of two numbers then need to use round
   SELECT CASE WHEN split_part(c.val,',', 2) > ''
        THEN round( split_part(c.val, ',',1)::numeric, split_part(c.val,',',2)::integer )::float8
        ELSE c.val::float8 END
        FROM c;
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_scale(rastschema name, rasttable name, rastcolumn name, axis char)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr double precision;
	BEGIN
		IF lower($4) != 'x' AND lower($4) != 'y' THEN
			RAISE EXCEPTION 'axis must be either "x" or "y"';
			RETURN FALSE;
		END IF;

		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_scale' || $4 || '_' || $3;

		sql := 'SELECT st_scale' || $4 || '('
			|| quote_ident($3)
			|| ') FROM '
			|| fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1;';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the %-scale of a sample raster: % (%)',
        upper($4), SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK (round(st_scale' || $4 || '('
			|| quote_ident($3)
			|| ')::numeric, 10) = round(' || text(attr) || '::numeric, 10))';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_scale(rastschema name, rasttable name, rastcolumn name, axis char)
	RETURNS boolean AS $$
	BEGIN
		IF lower($4) != 'x' AND lower($4) != 'y' THEN
			RAISE EXCEPTION 'axis must be either "x" or "y"';
			RETURN FALSE;
		END IF;

		RETURN  @extschema@._drop_raster_constraint($1, $2, 'enforce_scale' || $4 || '_' || $3);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_blocksize(rastschema name, rasttable name, rastcolumn name, axis text)
	RETURNS integer AS $$
	SELECT
		CASE
			WHEN strpos(s.consrc, 'ANY (ARRAY[') > 0 THEN
				split_part((substring(s.consrc FROM E'ARRAY\\[(.*?){1}\\]')), ',', 1)::integer
			ELSE
				regexp_replace(
					split_part(s.consrc, '= ', 2),
					'[\(\)]', '', 'g'
				)::integer
			END
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_' || $4 || '(%= %';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_blocksize(rastschema name, rasttable name, rastcolumn name, axis text)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attrset integer[];
		attr integer;
	BEGIN
		IF lower($4) != 'width' AND lower($4) != 'height' THEN
			RAISE EXCEPTION 'axis must be either "width" or "height"';
			RETURN FALSE;
		END IF;

		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_' || $4 || '_' || $3;

		sql := 'SELECT st_' || $4 || '('
			|| quote_ident($3)
			|| ') FROM ' || fqtn
			|| ' GROUP BY 1 ORDER BY count(*) DESC';
		BEGIN
			attrset := ARRAY[]::integer[];
			FOR attr IN EXECUTE sql LOOP
				attrset := attrset || attr;
			END LOOP;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the % of a sample raster: % (%)',
        $4, SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK (st_' || $4 || '('
			|| quote_ident($3)
			|| ') IN (' || array_to_string(attrset, ',') || '))';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_blocksize(rastschema name, rasttable name, rastcolumn name, axis text)
	RETURNS boolean AS $$
	BEGIN
		IF lower($4) != 'width' AND lower($4) != 'height' THEN
			RAISE EXCEPTION 'axis must be either "width" or "height"';
			RETURN FALSE;
		END IF;

		RETURN  @extschema@._drop_raster_constraint($1, $2, 'enforce_' || $4 || '_' || $3);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_extent(rastschema name, rasttable name, rastcolumn name)
	RETURNS geometry AS $$
	SELECT
		trim(both '''' from split_part(trim(split_part(s.consrc, ' @ ', 2)), '::', 1))::geometry
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_envelope(% @ %';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_extent(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr text; srid integer;
	BEGIN
		fqtn := '';
		IF length(rastschema) > 0 THEN
			fqtn := quote_ident(rastschema) || '.';
		END IF;
		fqtn := fqtn || quote_ident(rasttable);

		sql := 'SELECT @extschema@.ST_SRID('
			|| quote_ident(rastcolumn)
			|| ') FROM '
			|| fqtn
			|| ' WHERE '
			|| quote_ident(rastcolumn)
			|| ' IS NOT NULL LIMIT 1;';
                EXECUTE sql INTO srid;

    IF srid IS NULL THEN
      RETURN false;
    END IF;

		cn := 'enforce_max_extent_' || rastcolumn;

		sql := 'SELECT @extschema@.st_ashexewkb( @extschema@.st_setsrid( @extschema@.st_extent( @extschema@.st_envelope('
			|| quote_ident(rastcolumn)
			|| ')), ' || srid || ')) FROM '
			|| fqtn;
		EXECUTE sql INTO attr;

		-- NOTE: I put NOT VALID to prevent the costly step of validating the constraint
		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK ( @extschema@.st_envelope('
			|| quote_ident(rastcolumn)
			|| ') @ ''' || attr || '''::geometry) NOT VALID';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 9000;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_extent(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_max_extent_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_alignment(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	SELECT
		TRUE
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_samealignment(%';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_alignment(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr text;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_same_alignment_' || $3;

		sql := 'SELECT @extschema@.st_makeemptyraster(1, 1, upperleftx, upperlefty, scalex, scaley, skewx, skewy, srid) FROM @extschema@.st_metadata((SELECT '
			|| quote_ident($3)
			|| ' FROM '
			|| fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1))';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the alignment of a sample raster: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;

		sql := 'ALTER TABLE ' || fqtn ||
			' ADD CONSTRAINT ' || quote_ident(cn) ||
			' CHECK (st_samealignment(' || quote_ident($3) || ', ''' || attr || '''::raster))';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_alignment(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_same_alignment_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_spatially_unique(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	SELECT
		TRUE
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conindid, conkey, contype, conexclop, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
		, pg_index idx, pg_operator op
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND s.contype = 'x'
		AND 0::smallint = ANY (s.conkey)
		AND idx.indexrelid = s.conindid
		AND pg_get_indexdef(idx.indexrelid, 1, true) LIKE '(' || quote_ident($3) || '::geometry)'
		AND s.conexclop[1] = op.oid
		AND op.oprname = '=';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_spatially_unique(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr text;
		meta record;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_spatially_unique_' || quote_ident($2) || '_'|| $3;

		sql := 'ALTER TABLE ' || fqtn ||
			' ADD CONSTRAINT ' || quote_ident(cn) ||
			' EXCLUDE ((' || quote_ident($3) || '::geometry) WITH =)';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_spatially_unique(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		cn text;
	BEGIN
		SELECT
			s.conname INTO cn
		FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conname, conrelid, conkey, conindid, contype, conexclop, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
		, pg_index idx, pg_operator op
		WHERE n.nspname = $1
			AND c.relname = $2
			AND a.attname = $3
			AND a.attrelid = c.oid
			AND s.connamespace = n.oid
			AND s.conrelid = c.oid
			AND s.contype = 'x'
			AND 0::smallint = ANY (s.conkey)
			AND idx.indexrelid = s.conindid
			AND pg_get_indexdef(idx.indexrelid, 1, true) LIKE '(' || quote_ident($3) || '::geometry)'
			AND s.conexclop[1] = op.oid
			AND op.oprname = '=';

		RETURN  @extschema@._drop_raster_constraint($1, $2, cn);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_coverage_tile(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	SELECT
		TRUE
	FROM pg_class c, pg_namespace n, pg_attribute a
			, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_iscoveragetile(%';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_coverage_tile(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;

		_scalex double precision;
		_scaley double precision;
		_skewx double precision;
		_skewy double precision;
		_tilewidth integer;
		_tileheight integer;
		_alignment boolean;

		_covextent @extschema@.geometry;
		_covrast @extschema@.raster;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_coverage_tile_' || $3;

		-- metadata
		BEGIN
			sql := 'WITH foo AS (SELECT @extschema@.ST_Metadata(' || quote_ident($3) || ') AS meta, @extschema@.ST_ConvexHull(' || quote_ident($3) || ') AS hull FROM ' || fqtn || ') SELECT max((meta).scalex), max((meta).scaley), max((meta).skewx), max((meta).skewy), max((meta).width), max((meta).height), @extschema@.ST_Union(hull) FROM foo';
			EXECUTE sql INTO _scalex, _scaley, _skewx, _skewy, _tilewidth, _tileheight, _covextent;
		EXCEPTION WHEN OTHERS THEN
			RAISE DEBUG 'Unable to get coverage metadata for %.%: % (%)',
        fqtn, quote_ident($3), SQLERRM, SQLSTATE;
      -- TODO: Why not return false here ?
		END;

		-- rasterize extent
		BEGIN
			_covrast := @extschema@.ST_AsRaster(_covextent, _scalex, _scaley, '8BUI', 1, 0, NULL, NULL, _skewx, _skewy);
			IF _covrast IS NULL THEN
				RAISE NOTICE 'Unable to create coverage raster. Cannot add coverage tile constraint: % (%)',
          SQLERRM, SQLSTATE;
				RETURN FALSE;
			END IF;

			-- remove band
			_covrast := ST_MakeEmptyRaster(_covrast);
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to create coverage raster. Cannot add coverage tile constraint: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;

		sql := 'ALTER TABLE ' || fqtn ||
			' ADD CONSTRAINT ' || quote_ident(cn) ||
			' CHECK (st_iscoveragetile(' || quote_ident($3) || ', ''' || _covrast || '''::raster, ' || _tilewidth || ', ' || _tileheight || '))';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_coverage_tile(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_coverage_tile_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_regular_blocking(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean
	AS $$
	DECLARE
		covtile boolean;
		spunique boolean;
	BEGIN
		-- check existance of constraints
		-- coverage tile constraint
		covtile := COALESCE( @extschema@._raster_constraint_info_coverage_tile($1, $2, $3), FALSE);

		-- spatially unique constraint
		spunique := COALESCE( @extschema@._raster_constraint_info_spatially_unique($1, $2, $3), FALSE);

		RETURN (covtile AND spunique);
	END;
	$$ LANGUAGE 'plpgsql' STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_regular_blocking(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT @extschema@._drop_raster_constraint($1, $2, 'enforce_regular_blocking_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_num_bands(rastschema name, rasttable name, rastcolumn name)
	RETURNS integer AS $$
	SELECT
		regexp_replace(
			split_part(s.consrc, ' = ', 2),
			'[\(\)]', '', 'g'
		)::integer
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%st_numbands(%';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_raster_constraint_num_bands(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr int;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_num_bands_' || $3;

		sql := 'SELECT @extschema@.st_numbands(' || quote_ident($3)
			|| ') FROM '
			|| fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1;';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the number of bands of a sample raster: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK (@extschema@.st_numbands(' || quote_ident($3)
			|| ') = ' || attr
			|| ')';
		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_num_bands(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_num_bands_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_pixel_types(rastschema name, rasttable name, rastcolumn name)
	RETURNS text[] AS $$
	SELECT
		trim(
			both '''' from split_part(
				regexp_replace(
					split_part(s.consrc, ' = ', 2),
					'[\(\)]', '', 'g'
				),
				'::', 1
			)
		)::text[]
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%_raster_constraint_pixel_types(%';
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_pixel_types(rast raster)
	RETURNS text[] AS
	$$ SELECT array_agg(pixeltype)::text[] FROM  @extschema@.ST_BandMetaData($1, ARRAY[]::int[]); $$
	LANGUAGE 'sql' STABLE STRICT;
CREATE OR REPLACE FUNCTION _add_raster_constraint_pixel_types(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr text[];
		max int;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_pixel_types_' || $3;

		sql := 'SELECT @extschema@._raster_constraint_pixel_types(' || quote_ident($3)
			|| ') FROM ' || fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1;';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the pixel types of a sample raster: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;
		max := array_length(attr, 1);
		IF max < 1 OR max IS NULL THEN
			RAISE NOTICE 'Unable to get the pixel types of a sample raster (max < 1 or null)';
			RETURN FALSE;
		END IF;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK (_raster_constraint_pixel_types(' || quote_ident($3)
			|| ') = ''{';
		FOR x in 1..max LOOP
			sql := sql || '"' || attr[x] || '"';
			IF x < max THEN
				sql := sql || ',';
			END IF;
		END LOOP;
		sql := sql || '}''::text[])';

		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_pixel_types(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_pixel_types_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _raster_constraint_info_nodata_values(rastschema name, rasttable name, rastcolumn name)
	RETURNS double precision[] AS $$
	SELECT
		trim(both '''' from
			split_part(
				regexp_replace(
					split_part(s.consrc, ' = ', 2),
					'[\(\)]', '', 'g'
				),
				'::', 1
			)
		)::double precision[]
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%_raster_constraint_nodata_values(%';
	$$ LANGUAGE sql STABLE STRICT;
CREATE OR REPLACE FUNCTION _raster_constraint_nodata_values(rast raster)
	RETURNS numeric[] AS
	$$ SELECT array_agg(round(nodatavalue::numeric, 10))::numeric[] FROM @extschema@.ST_BandMetaData($1, ARRAY[]::int[]); $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _add_raster_constraint_nodata_values(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr numeric[];
		max int;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_nodata_values_' || $3;

		sql := 'SELECT @extschema@._raster_constraint_nodata_values(' || quote_ident($3)
			|| ') FROM ' || fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1;';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the nodata values of a sample raster: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;
		max := array_length(attr, 1);
		IF max < 1 OR max IS NULL THEN
			RAISE NOTICE 'Unable to get the nodata values of a sample raster (max < 1 or null)';
			RETURN FALSE;
		END IF;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK (_raster_constraint_nodata_values(' || quote_ident($3)
			|| ')::numeric[] = ''{';
		FOR x in 1..max LOOP
			IF attr[x] IS NULL THEN
				sql := sql || 'NULL';
			ELSE
				sql := sql || attr[x];
			END IF;
			IF x < max THEN
				sql := sql || ',';
			END IF;
		END LOOP;
		sql := sql || '}''::numeric[])';

		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_nodata_values(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_nodata_values_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT
	COST 100;
CREATE OR REPLACE FUNCTION _raster_constraint_info_out_db(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean[] AS $$
	SELECT
		trim(
			both '''' from split_part(
				regexp_replace(
					split_part(s.consrc, ' = ', 2),
					'[\(\)]', '', 'g'
				),
				'::', 1
			)
		)::boolean[]
	FROM pg_class c, pg_namespace n, pg_attribute a
			, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
			FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%_raster_constraint_out_db(%';
	$$ LANGUAGE sql STABLE STRICT;
CREATE OR REPLACE FUNCTION _raster_constraint_out_db(rast raster)
	RETURNS boolean[] AS
	$$ SELECT array_agg(isoutdb)::boolean[] FROM @extschema@.ST_BandMetaData($1, ARRAY[]::int[]); $$
	LANGUAGE 'sql' IMMUTABLE STRICT PARALLEL SAFE;
CREATE OR REPLACE FUNCTION _add_raster_constraint_out_db(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
		attr boolean[];
		max int;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_out_db_' || $3;

		sql := 'SELECT @extschema@._raster_constraint_out_db(' || quote_ident($3)
			|| ') FROM ' || fqtn
			|| ' WHERE '
			|| quote_ident($3)
			|| ' IS NOT NULL LIMIT 1;';
		BEGIN
			EXECUTE sql INTO attr;
		EXCEPTION WHEN OTHERS THEN
			RAISE NOTICE 'Unable to get the out-of-database bands of a sample raster: % (%)',
        SQLERRM, SQLSTATE;
			RETURN FALSE;
		END;
		max := array_length(attr, 1);
		IF max < 1 OR max IS NULL THEN
			RAISE NOTICE 'Unable to get the out-of-database bands of a sample raster (max < 1 or null)';
			RETURN FALSE;
		END IF;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK ( @extschema@._raster_constraint_out_db(' || quote_ident($3)
			|| ') = ''{';
		FOR x in 1..max LOOP
			IF attr[x] IS FALSE THEN
				sql := sql || 'FALSE';
			ELSE
				sql := sql || 'TRUE';
			END IF;
			IF x < max THEN
				sql := sql || ',';
			END IF;
		END LOOP;
		sql := sql || '}''::boolean[])';

		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _drop_raster_constraint_out_db(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_out_db_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _raster_constraint_info_index(rastschema name, rasttable name, rastcolumn name)
	RETURNS boolean AS $$
		SELECT
			TRUE
		FROM pg_catalog.pg_class c
		JOIN pg_catalog.pg_index i
			ON i.indexrelid = c.oid
		JOIN pg_catalog.pg_class c2
			ON i.indrelid = c2.oid
		JOIN pg_catalog.pg_namespace n
			ON n.oid = c.relnamespace
		JOIN pg_am am
			ON c.relam = am.oid
		JOIN pg_attribute att
			ON att.attrelid = c2.oid
				AND pg_catalog.format_type(att.atttypid, att.atttypmod) = 'raster'
		WHERE c.relkind IN ('i')
			AND n.nspname = $1
			AND c2.relname = $2
			AND att.attname = $3
			AND am.amname = 'gist'
			AND strpos(pg_catalog.pg_get_expr(i.indexprs, i.indrelid), att.attname) > 0;
	$$ LANGUAGE sql STABLE STRICT;
CREATE OR REPLACE FUNCTION AddRasterConstraints (
	rastschema name,
	rasttable name,
	rastcolumn name,
	VARIADIC constraints text[]
)
	RETURNS boolean
	AS $$
	DECLARE
		max int;
		cnt int;
		sql text;
		schema name;
		x int;
		kw text;
		rtn boolean;
	BEGIN
		cnt := 0;
		max := array_length(constraints, 1);
		IF max < 1 THEN
			RAISE NOTICE 'No constraints indicated to be added.  Doing nothing';
			RETURN TRUE;
		END IF;

		-- validate schema
		schema := NULL;
		IF length($1) > 0 THEN
			sql := 'SELECT nspname FROM pg_namespace '
				|| 'WHERE nspname = ' || quote_literal($1)
				|| 'LIMIT 1';
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The value provided for schema is invalid';
				RETURN FALSE;
			END IF;
		END IF;

		IF schema IS NULL THEN
			sql := 'SELECT n.nspname AS schemaname '
				|| 'FROM pg_catalog.pg_class c '
				|| 'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
				|| 'WHERE c.relkind = ' || quote_literal('r')
				|| ' AND n.nspname NOT IN (' || quote_literal('pg_catalog')
				|| ', ' || quote_literal('pg_toast')
				|| ') AND pg_catalog.pg_table_is_visible(c.oid)'
				|| ' AND c.relname = ' || quote_literal($2);
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The table % does not occur in the search_path', quote_literal($2);
				RETURN FALSE;
			END IF;
		END IF;

		<<kwloop>>
		FOR x in 1..max LOOP
			kw := trim(both from lower(constraints[x]));

			BEGIN
				CASE
					WHEN kw = 'srid' THEN
						RAISE NOTICE 'Adding SRID constraint';
						rtn :=  @extschema@._add_raster_constraint_srid(schema, $2, $3);
					WHEN kw IN ('scale_x', 'scalex') THEN
						RAISE NOTICE 'Adding scale-X constraint';
						rtn :=  @extschema@._add_raster_constraint_scale(schema, $2, $3, 'x');
					WHEN kw IN ('scale_y', 'scaley') THEN
						RAISE NOTICE 'Adding scale-Y constraint';
						rtn :=  @extschema@._add_raster_constraint_scale(schema, $2, $3, 'y');
					WHEN kw = 'scale' THEN
						RAISE NOTICE 'Adding scale-X constraint';
						rtn :=  @extschema@._add_raster_constraint_scale(schema, $2, $3, 'x');
						RAISE NOTICE 'Adding scale-Y constraint';
						rtn :=  @extschema@._add_raster_constraint_scale(schema, $2, $3, 'y');
					WHEN kw IN ('blocksize_x', 'blocksizex', 'width') THEN
						RAISE NOTICE 'Adding blocksize-X constraint';
						rtn :=  @extschema@._add_raster_constraint_blocksize(schema, $2, $3, 'width');
					WHEN kw IN ('blocksize_y', 'blocksizey', 'height') THEN
						RAISE NOTICE 'Adding blocksize-Y constraint';
						rtn :=  @extschema@._add_raster_constraint_blocksize(schema, $2, $3, 'height');
					WHEN kw = 'blocksize' THEN
						RAISE NOTICE 'Adding blocksize-X constraint';
						rtn :=  @extschema@._add_raster_constraint_blocksize(schema, $2, $3, 'width');
						RAISE NOTICE 'Adding blocksize-Y constraint';
						rtn :=  @extschema@._add_raster_constraint_blocksize(schema, $2, $3, 'height');
					WHEN kw IN ('same_alignment', 'samealignment', 'alignment') THEN
						RAISE NOTICE 'Adding alignment constraint';
						rtn :=  @extschema@._add_raster_constraint_alignment(schema, $2, $3);
					WHEN kw IN ('regular_blocking', 'regularblocking') THEN
						RAISE NOTICE 'Adding coverage tile constraint required for regular blocking';
						rtn :=  @extschema@._add_raster_constraint_coverage_tile(schema, $2, $3);
						IF rtn IS NOT FALSE THEN
							RAISE NOTICE 'Adding spatially unique constraint required for regular blocking';
							rtn :=  @extschema@._add_raster_constraint_spatially_unique(schema, $2, $3);
						END IF;
					WHEN kw IN ('num_bands', 'numbands') THEN
						RAISE NOTICE 'Adding number of bands constraint';
						rtn :=  @extschema@._add_raster_constraint_num_bands(schema, $2, $3);
					WHEN kw IN ('pixel_types', 'pixeltypes') THEN
						RAISE NOTICE 'Adding pixel type constraint';
						rtn :=  @extschema@._add_raster_constraint_pixel_types(schema, $2, $3);
					WHEN kw IN ('nodata_values', 'nodatavalues', 'nodata') THEN
						RAISE NOTICE 'Adding nodata value constraint';
						rtn :=  @extschema@._add_raster_constraint_nodata_values(schema, $2, $3);
					WHEN kw IN ('out_db', 'outdb') THEN
						RAISE NOTICE 'Adding out-of-database constraint';
						rtn :=  @extschema@._add_raster_constraint_out_db(schema, $2, $3);
					WHEN kw = 'extent' THEN
						RAISE NOTICE 'Adding maximum extent constraint';
						rtn :=  @extschema@._add_raster_constraint_extent(schema, $2, $3);
					ELSE
						RAISE NOTICE 'Unknown constraint: %.  Skipping', quote_literal(constraints[x]);
						CONTINUE kwloop;
				END CASE;
			END;

			IF rtn IS FALSE THEN
				cnt := cnt + 1;
				RAISE WARNING 'Unable to add constraint: %.  Skipping', quote_literal(constraints[x]);
			END IF;

		END LOOP kwloop;

		IF cnt = max THEN
			RAISE EXCEPTION 'None of the constraints specified could be added.  Is the schema name, table name or column name incorrect?';
			RETURN FALSE;
		END IF;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION AddRasterConstraints (
	rasttable name,
	rastcolumn name,
	VARIADIC constraints text[]
)
	RETURNS boolean AS
	$$ SELECT @extschema@.AddRasterConstraints('', $1, $2, VARIADIC $3) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION AddRasterConstraints (
	rastschema name,
	rasttable name,
	rastcolumn name,
	srid boolean DEFAULT TRUE,
	scale_x boolean DEFAULT TRUE,
	scale_y boolean DEFAULT TRUE,
	blocksize_x boolean DEFAULT TRUE,
	blocksize_y boolean DEFAULT TRUE,
	same_alignment boolean DEFAULT TRUE,
	regular_blocking boolean DEFAULT FALSE, -- false as regular_blocking is an enhancement
	num_bands boolean DEFAULT TRUE,
	pixel_types boolean DEFAULT TRUE,
	nodata_values boolean DEFAULT TRUE,
	out_db boolean DEFAULT TRUE,
	extent boolean DEFAULT TRUE
)
	RETURNS boolean
	AS $$
	DECLARE
		constraints text[];
	BEGIN
		IF srid IS TRUE THEN
			constraints := constraints || 'srid'::text;
		END IF;

		IF scale_x IS TRUE THEN
			constraints := constraints || 'scale_x'::text;
		END IF;

		IF scale_y IS TRUE THEN
			constraints := constraints || 'scale_y'::text;
		END IF;

		IF blocksize_x IS TRUE THEN
			constraints := constraints || 'blocksize_x'::text;
		END IF;

		IF blocksize_y IS TRUE THEN
			constraints := constraints || 'blocksize_y'::text;
		END IF;

		IF same_alignment IS TRUE THEN
			constraints := constraints || 'same_alignment'::text;
		END IF;

		IF regular_blocking IS TRUE THEN
			constraints := constraints || 'regular_blocking'::text;
		END IF;

		IF num_bands IS TRUE THEN
			constraints := constraints || 'num_bands'::text;
		END IF;

		IF pixel_types IS TRUE THEN
			constraints := constraints || 'pixel_types'::text;
		END IF;

		IF nodata_values IS TRUE THEN
			constraints := constraints || 'nodata_values'::text;
		END IF;

		IF out_db IS TRUE THEN
			constraints := constraints || 'out_db'::text;
		END IF;

		IF extent IS TRUE THEN
			constraints := constraints || 'extent'::text;
		END IF;

		RETURN @extschema@.AddRasterConstraints($1, $2, $3, VARIADIC constraints);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION AddRasterConstraints (
	rasttable name,
	rastcolumn name,
	srid boolean DEFAULT TRUE,
	scale_x boolean DEFAULT TRUE,
	scale_y boolean DEFAULT TRUE,
	blocksize_x boolean DEFAULT TRUE,
	blocksize_y boolean DEFAULT TRUE,
	same_alignment boolean DEFAULT TRUE,
	regular_blocking boolean DEFAULT FALSE, -- false as regular_blocking is an enhancement
	num_bands boolean DEFAULT TRUE,
	pixel_types boolean DEFAULT TRUE,
	nodata_values boolean DEFAULT TRUE,
	out_db boolean DEFAULT TRUE,
	extent boolean DEFAULT TRUE
)
	RETURNS boolean AS
	$$ SELECT @extschema@.AddRasterConstraints('', $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION DropRasterConstraints (
	rastschema name,
	rasttable name,
	rastcolumn name,
	VARIADIC constraints text[]
)
	RETURNS boolean
	AS $$
	DECLARE
		max int;
		x int;
		schema name;
		sql text;
		kw text;
		rtn boolean;
		cnt int;
	BEGIN
		cnt := 0;
		max := array_length(constraints, 1);
		IF max < 1 THEN
			RAISE NOTICE 'No constraints indicated to be dropped.  Doing nothing';
			RETURN TRUE;
		END IF;

		-- validate schema
		schema := NULL;
		IF length($1) > 0 THEN
			sql := 'SELECT nspname FROM pg_namespace '
				|| 'WHERE nspname = ' || quote_literal($1)
				|| 'LIMIT 1';
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The value provided for schema is invalid';
				RETURN FALSE;
			END IF;
		END IF;

		IF schema IS NULL THEN
			sql := 'SELECT n.nspname AS schemaname '
				|| 'FROM pg_catalog.pg_class c '
				|| 'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
				|| 'WHERE c.relkind = ' || quote_literal('r')
				|| ' AND n.nspname NOT IN (' || quote_literal('pg_catalog')
				|| ', ' || quote_literal('pg_toast')
				|| ') AND pg_catalog.pg_table_is_visible(c.oid)'
				|| ' AND c.relname = ' || quote_literal($2);
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The table % does not occur in the search_path', quote_literal($2);
				RETURN FALSE;
			END IF;
		END IF;

		<<kwloop>>
		FOR x in 1..max LOOP
			kw := trim(both from lower(constraints[x]));

			BEGIN
				CASE
					WHEN kw = 'srid' THEN
						RAISE NOTICE 'Dropping SRID constraint';
						rtn :=  @extschema@._drop_raster_constraint_srid(schema, $2, $3);
					WHEN kw IN ('scale_x', 'scalex') THEN
						RAISE NOTICE 'Dropping scale-X constraint';
						rtn :=  @extschema@._drop_raster_constraint_scale(schema, $2, $3, 'x');
					WHEN kw IN ('scale_y', 'scaley') THEN
						RAISE NOTICE 'Dropping scale-Y constraint';
						rtn :=  @extschema@._drop_raster_constraint_scale(schema, $2, $3, 'y');
					WHEN kw = 'scale' THEN
						RAISE NOTICE 'Dropping scale-X constraint';
						rtn :=  @extschema@._drop_raster_constraint_scale(schema, $2, $3, 'x');
						RAISE NOTICE 'Dropping scale-Y constraint';
						rtn :=  @extschema@._drop_raster_constraint_scale(schema, $2, $3, 'y');
					WHEN kw IN ('blocksize_x', 'blocksizex', 'width') THEN
						RAISE NOTICE 'Dropping blocksize-X constraint';
						rtn :=  @extschema@._drop_raster_constraint_blocksize(schema, $2, $3, 'width');
					WHEN kw IN ('blocksize_y', 'blocksizey', 'height') THEN
						RAISE NOTICE 'Dropping blocksize-Y constraint';
						rtn :=  @extschema@._drop_raster_constraint_blocksize(schema, $2, $3, 'height');
					WHEN kw = 'blocksize' THEN
						RAISE NOTICE 'Dropping blocksize-X constraint';
						rtn :=  @extschema@._drop_raster_constraint_blocksize(schema, $2, $3, 'width');
						RAISE NOTICE 'Dropping blocksize-Y constraint';
						rtn :=  @extschema@._drop_raster_constraint_blocksize(schema, $2, $3, 'height');
					WHEN kw IN ('same_alignment', 'samealignment', 'alignment') THEN
						RAISE NOTICE 'Dropping alignment constraint';
						rtn :=  @extschema@._drop_raster_constraint_alignment(schema, $2, $3);
					WHEN kw IN ('regular_blocking', 'regularblocking') THEN
						rtn :=  @extschema@._drop_raster_constraint_regular_blocking(schema, $2, $3);

						RAISE NOTICE 'Dropping coverage tile constraint required for regular blocking';
						rtn :=  @extschema@._drop_raster_constraint_coverage_tile(schema, $2, $3);

						IF rtn IS NOT FALSE THEN
							RAISE NOTICE 'Dropping spatially unique constraint required for regular blocking';
							rtn :=  @extschema@._drop_raster_constraint_spatially_unique(schema, $2, $3);
						END IF;
					WHEN kw IN ('num_bands', 'numbands') THEN
						RAISE NOTICE 'Dropping number of bands constraint';
						rtn :=  @extschema@._drop_raster_constraint_num_bands(schema, $2, $3);
					WHEN kw IN ('pixel_types', 'pixeltypes') THEN
						RAISE NOTICE 'Dropping pixel type constraint';
						rtn :=  @extschema@._drop_raster_constraint_pixel_types(schema, $2, $3);
					WHEN kw IN ('nodata_values', 'nodatavalues', 'nodata') THEN
						RAISE NOTICE 'Dropping nodata value constraint';
						rtn :=  @extschema@._drop_raster_constraint_nodata_values(schema, $2, $3);
					WHEN kw IN ('out_db', 'outdb') THEN
						RAISE NOTICE 'Dropping out-of-database constraint';
						rtn :=  @extschema@._drop_raster_constraint_out_db(schema, $2, $3);
					WHEN kw = 'extent' THEN
						RAISE NOTICE 'Dropping maximum extent constraint';
						rtn :=  @extschema@._drop_raster_constraint_extent(schema, $2, $3);
					ELSE
						RAISE NOTICE 'Unknown constraint: %.  Skipping', quote_literal(constraints[x]);
						CONTINUE kwloop;
				END CASE;
			END;

			IF rtn IS FALSE THEN
				cnt := cnt + 1;
				RAISE WARNING 'Unable to drop constraint: %.  Skipping', quote_literal(constraints[x]);
			END IF;

		END LOOP kwloop;

		IF cnt = max THEN
			RAISE EXCEPTION 'None of the constraints specified could be dropped.  Is the schema name, table name or column name incorrect?';
			RETURN FALSE;
		END IF;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION DropRasterConstraints (
	rasttable name,
	rastcolumn name,
	VARIADIC constraints text[]
)
	RETURNS boolean AS
	$$ SELECT  @extschema@.DropRasterConstraints('', $1, $2, VARIADIC $3) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION DropRasterConstraints (
	rastschema name,
	rasttable name,
	rastcolumn name,
	srid boolean DEFAULT TRUE,
	scale_x boolean DEFAULT TRUE,
	scale_y boolean DEFAULT TRUE,
	blocksize_x boolean DEFAULT TRUE,
	blocksize_y boolean DEFAULT TRUE,
	same_alignment boolean DEFAULT TRUE,
	regular_blocking boolean DEFAULT TRUE,
	num_bands boolean DEFAULT TRUE,
	pixel_types boolean DEFAULT TRUE,
	nodata_values boolean DEFAULT TRUE,
	out_db boolean DEFAULT TRUE,
	extent boolean DEFAULT TRUE
)
	RETURNS boolean
	AS $$
	DECLARE
		constraints text[];
	BEGIN
		IF srid IS TRUE THEN
			constraints := constraints || 'srid'::text;
		END IF;

		IF scale_x IS TRUE THEN
			constraints := constraints || 'scale_x'::text;
		END IF;

		IF scale_y IS TRUE THEN
			constraints := constraints || 'scale_y'::text;
		END IF;

		IF blocksize_x IS TRUE THEN
			constraints := constraints || 'blocksize_x'::text;
		END IF;

		IF blocksize_y IS TRUE THEN
			constraints := constraints || 'blocksize_y'::text;
		END IF;

		IF same_alignment IS TRUE THEN
			constraints := constraints || 'same_alignment'::text;
		END IF;

		IF regular_blocking IS TRUE THEN
			constraints := constraints || 'regular_blocking'::text;
		END IF;

		IF num_bands IS TRUE THEN
			constraints := constraints || 'num_bands'::text;
		END IF;

		IF pixel_types IS TRUE THEN
			constraints := constraints || 'pixel_types'::text;
		END IF;

		IF nodata_values IS TRUE THEN
			constraints := constraints || 'nodata_values'::text;
		END IF;

		IF out_db IS TRUE THEN
			constraints := constraints || 'out_db'::text;
		END IF;

		IF extent IS TRUE THEN
			constraints := constraints || 'extent'::text;
		END IF;

		RETURN DropRasterConstraints($1, $2, $3, VARIADIC constraints);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION DropRasterConstraints (
	rasttable name,
	rastcolumn name,
	srid boolean DEFAULT TRUE,
	scale_x boolean DEFAULT TRUE,
	scale_y boolean DEFAULT TRUE,
	blocksize_x boolean DEFAULT TRUE,
	blocksize_y boolean DEFAULT TRUE,
	same_alignment boolean DEFAULT TRUE,
	regular_blocking boolean DEFAULT TRUE,
	num_bands boolean DEFAULT TRUE,
	pixel_types boolean DEFAULT TRUE,
	nodata_values boolean DEFAULT TRUE,
	out_db boolean DEFAULT TRUE,
	extent boolean DEFAULT TRUE
)
	RETURNS boolean AS
	$$ SELECT DropRasterConstraints('', $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE VIEW raster_columns AS
	SELECT
		current_database() AS r_table_catalog,
		n.nspname AS r_table_schema,
		c.relname AS r_table_name,
		a.attname AS r_raster_column,
		COALESCE(_raster_constraint_info_srid(n.nspname, c.relname, a.attname), (SELECT ST_SRID('POINT(0 0)'::geometry))) AS srid,
		_raster_constraint_info_scale(n.nspname, c.relname, a.attname, 'x') AS scale_x,
		_raster_constraint_info_scale(n.nspname, c.relname, a.attname, 'y') AS scale_y,
		_raster_constraint_info_blocksize(n.nspname, c.relname, a.attname, 'width') AS blocksize_x,
		_raster_constraint_info_blocksize(n.nspname, c.relname, a.attname, 'height') AS blocksize_y,
		COALESCE(_raster_constraint_info_alignment(n.nspname, c.relname, a.attname), FALSE) AS same_alignment,
		COALESCE(_raster_constraint_info_regular_blocking(n.nspname, c.relname, a.attname), FALSE) AS regular_blocking,
		_raster_constraint_info_num_bands(n.nspname, c.relname, a.attname) AS num_bands,
		_raster_constraint_info_pixel_types(n.nspname, c.relname, a.attname) AS pixel_types,
		_raster_constraint_info_nodata_values(n.nspname, c.relname, a.attname) AS nodata_values,
		_raster_constraint_info_out_db(n.nspname, c.relname, a.attname) AS out_db,
		_raster_constraint_info_extent(n.nspname, c.relname, a.attname) AS extent,
		COALESCE(_raster_constraint_info_index(n.nspname, c.relname, a.attname), FALSE) AS spatial_index
	FROM
		pg_class c,
		pg_attribute a,
		pg_type t,
		pg_namespace n
	WHERE t.typname = 'raster'::name
		AND a.attisdropped = false
		AND a.atttypid = t.oid
		AND a.attrelid = c.oid
		AND c.relnamespace = n.oid
		AND c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"] )
		AND NOT pg_is_other_temp_schema(c.relnamespace)  AND has_table_privilege(c.oid, 'SELECT'::text);
CREATE OR REPLACE FUNCTION _overview_constraint(ov raster, factor integer, refschema name, reftable name, refcolumn name)
	RETURNS boolean AS
	$$ SELECT COALESCE((SELECT TRUE FROM @extschema@.raster_columns WHERE r_table_catalog = current_database() AND r_table_schema = $3 AND r_table_name = $4 AND r_raster_column = $5), FALSE) $$
	LANGUAGE 'sql' STABLE
	COST 100;
CREATE OR REPLACE FUNCTION _overview_constraint_info(
	ovschema name, ovtable name, ovcolumn name,
		OUT refschema name,
		OUT reftable name,
		OUT refcolumn name,
		OUT factor integer
	)
	AS $$
	SELECT
		split_part(split_part(s.consrc, '''::name', 1), '''', 2)::name,
		split_part(split_part(s.consrc, '''::name', 2), '''', 2)::name,
		split_part(split_part(s.consrc, '''::name', 3), '''', 2)::name,
		trim(both from split_part(s.consrc, ',', 2))::integer
	FROM pg_class c, pg_namespace n, pg_attribute a
		, (SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
		    FROM pg_constraint) AS s
	WHERE n.nspname = $1
		AND c.relname = $2
		AND a.attname = $3
		AND a.attrelid = c.oid
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND a.attnum = ANY (s.conkey)
		AND s.consrc LIKE '%_overview_constraint(%' LIMIT 1
	$$ LANGUAGE sql STABLE STRICT
  COST 100;
CREATE OR REPLACE FUNCTION _add_overview_constraint(
	ovschema name, ovtable name, ovcolumn name,
	refschema name, reftable name, refcolumn name,
	factor integer
)
	RETURNS boolean AS $$
	DECLARE
		fqtn text;
		cn name;
		sql text;
	BEGIN
		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		cn := 'enforce_overview_' || $3;

		sql := 'ALTER TABLE ' || fqtn
			|| ' ADD CONSTRAINT ' || quote_ident(cn)
			|| ' CHECK ( @extschema@._overview_constraint(' || quote_ident($3)
			|| ',' || $7
			|| ',' || quote_literal($4)
			|| ',' || quote_literal($5)
			|| ',' || quote_literal($6)
			|| '))';

		RETURN  @extschema@._add_raster_constraint(cn, sql);
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _drop_overview_constraint(ovschema name, ovtable name, ovcolumn name)
	RETURNS boolean AS
	$$ SELECT  @extschema@._drop_raster_constraint($1, $2, 'enforce_overview_' || $3) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE VIEW raster_overviews AS
	SELECT
		current_database() AS o_table_catalog,
		n.nspname AS o_table_schema,
		c.relname AS o_table_name,
		a.attname AS o_raster_column,
		current_database() AS r_table_catalog,
		split_part(split_part(s.consrc, '''::name', 1), '''', 2)::name AS r_table_schema,
		split_part(split_part(s.consrc, '''::name', 2), '''', 2)::name AS r_table_name,
		split_part(split_part(s.consrc, '''::name', 3), '''', 2)::name AS r_raster_column,
		trim(both from split_part(s.consrc, ',', 2))::integer AS overview_factor
	FROM
		pg_class c,
		pg_attribute a,
		pg_type t,
		pg_namespace n,
		(SELECT connamespace, conrelid, conkey, pg_get_constraintdef(oid) As consrc
		    FROM pg_constraint) AS s
	WHERE t.typname = 'raster'::name
		AND a.attisdropped = false
		AND a.atttypid = t.oid
		AND a.attrelid = c.oid
		AND c.relnamespace = n.oid
		AND c.relkind = ANY(ARRAY['r'::char, 'v'::char, 'm'::char, 'f'::char])
		AND s.connamespace = n.oid
		AND s.conrelid = c.oid
		AND s.consrc LIKE '%_overview_constraint(%'
		AND NOT pg_is_other_temp_schema(c.relnamespace)  AND has_table_privilege(c.oid, 'SELECT'::text);
CREATE OR REPLACE FUNCTION AddOverviewConstraints (
	ovschema name, ovtable name, ovcolumn name,
	refschema name, reftable name, refcolumn name,
	ovfactor int
)
	RETURNS boolean
	AS $$
	DECLARE
		x int;
		s name;
		t name;
		oschema name;
		rschema name;
		sql text;
		rtn boolean;
	BEGIN
		FOR x IN 1..2 LOOP
			s := '';

			IF x = 1 THEN
				s := $1;
				t := $2;
			ELSE
				s := $4;
				t := $5;
			END IF;

			-- validate user-provided schema
			IF length(s) > 0 THEN
				sql := 'SELECT nspname FROM pg_namespace '
					|| 'WHERE nspname = ' || quote_literal(s)
					|| 'LIMIT 1';
				EXECUTE sql INTO s;

				IF s IS NULL THEN
					RAISE EXCEPTION 'The value % is not a valid schema', quote_literal(s);
					RETURN FALSE;
				END IF;
			END IF;

			-- no schema, determine what it could be using the table
			IF length(s) < 1 THEN
				sql := 'SELECT n.nspname AS schemaname '
					|| 'FROM pg_catalog.pg_class c '
					|| 'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
					|| 'WHERE c.relkind = ' || quote_literal('r')
					|| ' AND n.nspname NOT IN (' || quote_literal('pg_catalog')
					|| ', ' || quote_literal('pg_toast')
					|| ') AND pg_catalog.pg_table_is_visible(c.oid)'
					|| ' AND c.relname = ' || quote_literal(t);
				EXECUTE sql INTO s;

				IF s IS NULL THEN
					RAISE EXCEPTION 'The table % does not occur in the search_path', quote_literal(t);
					RETURN FALSE;
				END IF;
			END IF;

			IF x = 1 THEN
				oschema := s;
			ELSE
				rschema := s;
			END IF;
		END LOOP;

		-- reference raster
		rtn :=  @extschema@._add_overview_constraint(oschema, $2, $3, rschema, $5, $6, $7);
		IF rtn IS FALSE THEN
			RAISE EXCEPTION 'Unable to add the overview constraint.  Is the schema name, table name or column name incorrect?';
			RETURN FALSE;
		END IF;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION AddOverviewConstraints (
	ovtable name, ovcolumn name,
	reftable name, refcolumn name,
	ovfactor int
)
	RETURNS boolean
	AS $$ SELECT  @extschema@.AddOverviewConstraints('', $1, $2, '', $3, $4, $5) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION DropOverviewConstraints (
	ovschema name,
	ovtable name,
	ovcolumn name
)
	RETURNS boolean
	AS $$
	DECLARE
		schema name;
		sql text;
		rtn boolean;
	BEGIN
		-- validate schema
		schema := NULL;
		IF length($1) > 0 THEN
			sql := 'SELECT nspname FROM pg_namespace '
				|| 'WHERE nspname = ' || quote_literal($1)
				|| 'LIMIT 1';
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The value provided for schema is invalid';
				RETURN FALSE;
			END IF;
		END IF;

		IF schema IS NULL THEN
			sql := 'SELECT n.nspname AS schemaname '
				|| 'FROM pg_catalog.pg_class c '
				|| 'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
				|| 'WHERE c.relkind = ' || quote_literal('r')
				|| ' AND n.nspname NOT IN (' || quote_literal('pg_catalog')
				|| ', ' || quote_literal('pg_toast')
				|| ') AND pg_catalog.pg_table_is_visible(c.oid)'
				|| ' AND c.relname = ' || quote_literal($2);
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The table % does not occur in the search_path', quote_literal($2);
				RETURN FALSE;
			END IF;
		END IF;

		rtn :=  @extschema@._drop_overview_constraint(schema, $2, $3);
		IF rtn IS FALSE THEN
			RAISE EXCEPTION 'Unable to drop the overview constraint .  Is the schema name, table name or column name incorrect?';
			RETURN FALSE;
		END IF;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION DropOverviewConstraints (
	ovtable name,
	ovcolumn name
)
	RETURNS boolean
	AS $$ SELECT  @extschema@.DropOverviewConstraints('', $1, $2) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION _UpdateRasterSRID(
	schema_name name, table_name name, column_name name,
	new_srid integer
)
	RETURNS boolean
	AS $$
	DECLARE
		fqtn text;
		schema name;
		sql text;
		srid integer;
		ct boolean;
	BEGIN
		-- validate schema
		schema := NULL;
		IF length($1) > 0 THEN
			sql := 'SELECT nspname FROM pg_namespace '
				|| 'WHERE nspname = ' || quote_literal($1)
				|| 'LIMIT 1';
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The value provided for schema is invalid';
				RETURN FALSE;
			END IF;
		END IF;

		IF schema IS NULL THEN
			sql := 'SELECT n.nspname AS schemaname '
				|| 'FROM pg_catalog.pg_class c '
				|| 'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
				|| 'WHERE c.relkind = ' || quote_literal('r')
				|| ' AND n.nspname NOT IN (' || quote_literal('pg_catalog')
				|| ', ' || quote_literal('pg_toast')
				|| ') AND pg_catalog.pg_table_is_visible(c.oid)'
				|| ' AND c.relname = ' || quote_literal($2);
			EXECUTE sql INTO schema;

			IF schema IS NULL THEN
				RAISE EXCEPTION 'The table % does not occur in the search_path', quote_literal($2);
				RETURN FALSE;
			END IF;
		END IF;

		-- clamp SRID
		IF new_srid < 0 THEN
			srid :=  @extschema@.ST_SRID('POINT EMPTY'::@extschema@.geometry);
			RAISE NOTICE 'SRID % converted to the officially unknown SRID %', new_srid, srid;
		ELSE
			srid := new_srid;
		END IF;

		-- drop coverage tile constraint
		-- done separately just in case constraint doesn't exist
		ct := @extschema@._raster_constraint_info_coverage_tile(schema, $2, $3);
		IF ct IS TRUE THEN
			PERFORM  @extschema@._drop_raster_constraint_coverage_tile(schema, $2, $3);
		END IF;

		-- drop SRID, extent, alignment constraints
		PERFORM  @extschema@.DropRasterConstraints(schema, $2, $3, 'extent', 'alignment', 'srid');

		fqtn := '';
		IF length($1) > 0 THEN
			fqtn := quote_ident($1) || '.';
		END IF;
		fqtn := fqtn || quote_ident($2);

		-- update SRID
		sql := 'UPDATE ' || fqtn ||
			' SET ' || quote_ident($3) ||
			' =  @extschema@.ST_SetSRID(' || quote_ident($3) ||
			'::@extschema@.raster, ' || srid || ')';
		RAISE NOTICE 'sql = %', sql;
		EXECUTE sql;

		-- add SRID constraint
		PERFORM  @extschema@.AddRasterConstraints(schema, $2, $3, 'srid', 'extent', 'alignment');

		-- add coverage tile constraint if needed
		IF ct IS TRUE THEN
			PERFORM  @extschema@._add_raster_constraint_coverage_tile(schema, $2, $3);
		END IF;

		RETURN TRUE;
	END;
	$$ LANGUAGE 'plpgsql' VOLATILE;
CREATE OR REPLACE FUNCTION UpdateRasterSRID(
	schema_name name, table_name name, column_name name,
	new_srid integer
)
	RETURNS boolean
	AS $$ SELECT  @extschema@._UpdateRasterSRID($1, $2, $3, $4) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION UpdateRasterSRID(
	table_name name, column_name name,
	new_srid integer
)
	RETURNS boolean
	AS $$ SELECT  @extschema@._UpdateRasterSRID('', $1, $2, $3) $$
	LANGUAGE 'sql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION ST_Retile(tab regclass, col name, ext geometry, sfx float8, sfy float8, tw int, th int, algo text DEFAULT 'NearestNeighbour')
RETURNS SETOF raster AS $$
DECLARE
  rec RECORD;
  ipx FLOAT8;
  ipy FLOAT8;
  tx int;
  ty int;
  te @extschema@.GEOMETRY; -- tile extent
  ncols int;
  nlins int;
  srid int;
  sql TEXT;
BEGIN

  RAISE DEBUG 'Target coverage will have sfx=%, sfy=%', sfx, sfy;

  -- 2. Loop over each target tile and build it from source tiles
  ipx := st_xmin(ext);
  ncols := ceil((st_xmax(ext)-ipx)/sfx/tw);
  IF sfy < 0 THEN
    ipy := st_ymax(ext);
    nlins := ceil((st_ymin(ext)-ipy)/sfy/th);
  ELSE
    ipy := st_ymin(ext);
    nlins := ceil((st_ymax(ext)-ipy)/sfy/th);
  END IF;

  srid := ST_Srid(ext);

  RAISE DEBUG 'Target coverage will have % x % tiles, each of approx size % x %', ncols, nlins, tw, th;
  RAISE DEBUG 'Target coverage will cover extent %', ext::box2d;

  FOR tx IN 0..ncols-1 LOOP
    FOR ty IN 0..nlins-1 LOOP
      te := ST_MakeEnvelope(ipx + tx     *  tw  * sfx,
                             ipy + ty     *  th  * sfy,
                             ipx + (tx+1) *  tw  * sfx,
                             ipy + (ty+1) *  th  * sfy,
                             srid);
      --RAISE DEBUG 'sfx/sfy: %, %', sfx, sfy;
      --RAISE DEBUG 'tile extent %', te;
      sql := 'SELECT count(*),  @extschema@.ST_Clip(  @extschema@.ST_Union(  @extschema@.ST_SnapToGrid(  @extschema@.ST_Rescale(  @extschema@.ST_Clip(' || quote_ident(col)
          || ',  @extschema@.ST_Expand($3, greatest($1,$2))),$1, $2, $6), $4, $5, $1, $2)), $3) g FROM ' || tab::text
          || ' WHERE  @extschema@.ST_Intersects(' || quote_ident(col) || ', $3)';
      --RAISE DEBUG 'SQL: %', sql;
      FOR rec IN EXECUTE sql USING sfx, sfy, te, ipx, ipy, algo LOOP
        --RAISE DEBUG '% source tiles intersect target tile %,% with extent %', rec.count, tx, ty, te::box2d;
        IF rec.g IS NULL THEN
          RAISE WARNING 'No source tiles cover target tile %,% with extent %',
            tx, ty, te::box2d;
        ELSE
          --RAISE DEBUG 'Tile for extent % has size % x %', te::box2d, st_width(rec.g), st_height(rec.g);
          RETURN NEXT rec.g;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  RETURN;
END;
$$ LANGUAGE 'plpgsql' STABLE STRICT;
CREATE OR REPLACE FUNCTION ST_CreateOverview(tab regclass, col name, factor int, algo text DEFAULT 'NearestNeighbour')
RETURNS regclass AS $$
DECLARE
  sinfo RECORD; -- source info
  sql TEXT;
  ttab TEXT;
BEGIN

  -- 0. Check arguments, we need to ensure:
  --    a. Source table has a raster column with given name
  --    b. Source table has a fixed scale (or "factor" would have no meaning)
  --    c. Source table has a known extent ? (we could actually compute it)
  --    d. Source table has a fixed tile size (or "factor" would have no meaning?)
  -- # all of the above can be checked with a query to raster_columns
  sql := 'SELECT r.r_table_schema sch, r.r_table_name tab, '
      || 'r.scale_x sfx, r.scale_y sfy, r.blocksize_x tw, '
      || 'r.blocksize_y th, r.extent ext, r.srid FROM @extschema@.raster_columns r, '
      || 'pg_class c, pg_namespace n WHERE r.r_table_schema = n.nspname '
      || 'AND r.r_table_name = c.relname AND r_raster_column = $2 AND '
      || ' c.relnamespace = n.oid AND c.oid = $1'
  ;
  EXECUTE sql INTO sinfo USING tab, col;
  IF sinfo IS NULL THEN
      RAISE EXCEPTION '%.% raster column does not exist', tab::text, col;
  END IF;
  IF sinfo.sfx IS NULL or sinfo.sfy IS NULL THEN
    RAISE EXCEPTION 'cannot create overview without scale constraint, try select AddRasterConstraints(''%'', ''%'');', tab::text, col;
  END IF;
  IF sinfo.tw IS NULL or sinfo.tw IS NULL THEN
    RAISE EXCEPTION 'cannot create overview without tilesize constraint, try select AddRasterConstraints(''%'', ''%'');', tab::text, col;
  END IF;
  IF sinfo.ext IS NULL THEN
    RAISE EXCEPTION 'cannot create overview without extent constraint, try select AddRasterConstraints(''%'', ''%'');', tab::text, col;
  END IF;

  -- TODO: lookup in raster_overviews to see if there's any
  --       lower-resolution table to start from

  ttab := 'o_' || factor || '_' || sinfo.tab;
  sql := 'CREATE TABLE ' || quote_ident(sinfo.sch)
      || '.' || quote_ident(ttab)
      || ' AS SELECT ST_Retile($1, $2, $3, $4, $5, $6, $7) '
      || quote_ident(col);
  EXECUTE sql USING tab, col, sinfo.ext,
                    sinfo.sfx * factor, sinfo.sfy * factor,
                    sinfo.tw, sinfo.th, algo;

  -- TODO: optimize this using knowledge we have about
  --       the characteristics of the target column ?
  PERFORM @extschema@.AddRasterConstraints(sinfo.sch, ttab, col);

  PERFORM  @extschema@.AddOverviewConstraints(sinfo.sch, ttab, col,
                                 sinfo.sch, sinfo.tab, col, factor);

    -- return the schema as well as the table
  RETURN sinfo.sch||'.'||ttab;
END;
$$ LANGUAGE 'plpgsql' VOLATILE STRICT;
CREATE OR REPLACE FUNCTION st_makeemptycoverage(tilewidth int, tileheight int, width int, height int, upperleftx float8, upperlefty float8, scalex float8, scaley float8, skewx float8, skewy float8, srid int4 DEFAULT 0)
    RETURNS SETOF RASTER AS $$
    DECLARE
        ulx double precision;  -- upper left x of raster
        uly double precision;  -- upper left y of raster
        rw int;                -- raster width (may change at edges)
        rh int;                -- raster height (may change at edges)
        x int;                 -- x index of coverage
        y int;                 -- y index of coverage
        template @extschema@.raster;       -- an empty template raster, where each cell
                               -- represents a tile in the coverage
        minY double precision;
        maxX double precision;
    BEGIN
        template := @extschema@.ST_MakeEmptyRaster(
            ceil(width::float8/tilewidth)::int,
            ceil(height::float8/tileheight)::int,
            upperleftx,
            upperlefty,
            tilewidth * scalex,
            tileheight * scaley,
            tileheight * skewx,
            tilewidth * skewy,
            srid
        );

        FOR y IN 1..st_height(template) LOOP
            maxX := @extschema@.ST_RasterToWorldCoordX(template, 1, y) + width * scalex;
            FOR x IN 1..st_width(template) LOOP
                minY := @extschema@.ST_RasterToWorldCoordY(template, x, 1) + height * scaley;
                uly := @extschema@.ST_RasterToWorldCoordY(template, x, y);
                IF uly + (tileheight * scaley) < minY THEN
                    --raise notice 'uly, minY: %, %', uly, minY;
                    rh := ceil((minY - uly)/scaleY)::int;
                ELSE
                    rh := tileheight;
                END IF;

                ulx := @extschema@.ST_RasterToWorldCoordX(template, x, y);
                IF ulx + (tilewidth * scalex) > maxX THEN
                    --raise notice 'ulx, maxX: %, %', ulx, maxX;
                    rw := ceil((maxX - ulx)/scaleX)::int;
                ELSE
                    rw := tilewidth;
                END IF;

                RETURN NEXT @extschema@.ST_MakeEmptyRaster(rw, rh, ulx, uly, scalex, scaley, skewx, skewy, srid);
            END LOOP;
        END LOOP;
    END;
    $$ LANGUAGE 'plpgsql' IMMUTABLE PARALLEL SAFE;
CREATE OR REPLACE FUNCTION postgis_noop(raster)
	RETURNS geometry
	AS '$libdir/postgis_raster-3', 'RASTER_noop'
	LANGUAGE 'c' STABLE STRICT;
GRANT SELECT ON TABLE raster_columns TO public;
GRANT SELECT ON TABLE raster_overviews TO public;
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION _postgis_upgrade_info()');
DROP FUNCTION _postgis_upgrade_info();











-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
--
-- PostGIS Raster - Raster Type for PostGIS
-- http://trac.osgeo.org/postgis/wiki/WKTRaster
--
-- Copyright (C) 2011 Regina Obe <lr@pcorp.us>
-- Copyright (C) 2011-2012 Regents of the University of California
-- <bkpark@ucdavis.edu>
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software Foundation,
-- Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
-- WARNING: Any change in this file must be evaluated for compatibility.
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
-- This file will be used to drop obseleted objects.
-- It will be only used for upgrades.
-- It will be loaded _after_ the objects upgrade statements, so
-- that objects previously dependent on these objects have a chance
-- to get upgraded to remove the dependency.
--
-- Remember: only put _obsoleted_ signatures in this file.
--
-- TODO: tag each item with the version in which it was dropped
--
--

-- drop obsoleted aggregates
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text, double precision, text, text, text, double precision, text, text, text, double precision)');
DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text, double precision, text, text, text, double precision, text, text, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text)');
DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text, double precision, text, text, text, double precision)');
DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text, double precision, text, text, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP AGGREGATE IF EXISTS ST_Union(raster, text, text)');
DROP AGGREGATE IF EXISTS ST_Union(raster, text, text);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text, double precision)');
DROP AGGREGATE IF EXISTS ST_Union(raster, text, text, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP AGGREGATE IF EXISTS ST_Union(raster, record[])');
DROP AGGREGATE IF EXISTS ST_Union(raster, record[]);

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersects(raster,boolean,geometry)');
DROP FUNCTION IF EXISTS ST_Intersects(raster,boolean,geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersects(geometry,raster,boolean)');
DROP FUNCTION IF EXISTS ST_Intersects(geometry,raster,boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersects(raster,geometry)');
DROP FUNCTION IF EXISTS ST_Intersects(raster,geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersects(geometry,raster)');
DROP FUNCTION IF EXISTS ST_Intersects(geometry,raster);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersects(raster, integer, boolean, geometry)');
DROP FUNCTION IF EXISTS ST_Intersects(raster, integer, boolean, geometry);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersects(geometry, raster, integer, boolean)');
DROP FUNCTION IF EXISTS ST_Intersects(geometry, raster, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersection(raster,raster, integer, integer)');
DROP FUNCTION IF EXISTS ST_Intersection(raster,raster, integer, integer);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS ST_Intersection(geometry,raster)');
DROP FUNCTION IF EXISTS ST_Intersection(geometry,raster);

-- Removed in 2.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra4unionfinal1(raster)');
DROP FUNCTION IF EXISTS _st_mapalgebra4unionfinal1(raster);
-- Removed in 2.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, int4)');
DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, int4);
-- Removed in 2.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster)');
DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster);
-- Removed in 2.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, text)');
DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, text);
-- Removed in 2.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, int4, text)');
DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, int4, text);
-- Removed in 2.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, text, text, text, float8, text, text, text, float8)');
DROP FUNCTION IF EXISTS _st_mapalgebra4unionstate(raster, raster, text, text, text, float8, text, text, text, float8);
-- Removed in 2.2.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_mapalgebra(rastbandarg[],regprocedure,text,integer,integer,text,raster,text[])');
DROP FUNCTION IF EXISTS _st_mapalgebra(rastbandarg[],regprocedure,text,integer,integer,text,raster,text[]);

-- Removed in 3.1.0
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_count(text, text, integer, boolean, double precision)');
DROP FUNCTION IF EXISTS _st_count(text, text, integer, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_count(text, text, int, boolean)');
DROP FUNCTION IF EXISTS st_count(text, text, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_count(text, text, boolean)');
DROP FUNCTION IF EXISTS st_count(text, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxcount(text, text, int, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxcount(text, text, int, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxcount(text, text, int, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxcount(text, text, int, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxcount(text, text, int, double precision)');
DROP FUNCTION IF EXISTS st_approxcount(text, text, int, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxcount(text, text, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxcount(text, text, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxcount(text, text, double precision)');
DROP FUNCTION IF EXISTS st_approxcount(text, text, double precision);

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_summarystats(text, text, integer, boolean, double precision)');
DROP FUNCTION IF EXISTS _st_summarystats(text, text, integer, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_summarystats(text, text, integer, boolean)');
DROP FUNCTION IF EXISTS st_summarystats(text, text, integer, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_summarystats(text, text, boolean)');
DROP FUNCTION IF EXISTS st_summarystats(text, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, integer, boolean, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, integer, boolean, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, integer, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, integer, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, boolean)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, double precision)');
DROP FUNCTION IF EXISTS st_approxsummarystats(text, text, double precision);

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_histogram(text, text, int, boolean, double precision, int,double precision[], boolean)');
DROP FUNCTION IF EXISTS _st_histogram(text, text, int, boolean, double precision, int,double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, boolean, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram(text, text, int, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_histogram(text, text, int, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_histogram( ext, text, int, int, boolean)');
DROP FUNCTION IF EXISTS st_histogram( ext, text, int, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, boolean, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, boolean, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, boolean, double precision, int, boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, boolean, double precision, int, boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int,double precision)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int,double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, double precision)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, double precision[], boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, double precision[], boolean);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, boolean)');
DROP FUNCTION IF EXISTS st_approxhistogram(text, text, int, double precision, int, boolean);


SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS _st_quantile( rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS _st_quantile( rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile( rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_quantile( rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile( rastertable text, rastercolumn text, nband int, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_quantile( rastertable text, rastercolumn text, nband int, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile( rastertable text, rastercolumn text, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_quantile( rastertable text, rastercolumn text, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, quantile double precision)');
DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, nband int, quantile double precision)');
DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, nband int, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, exclude_nodata_value boolean, quantile double precision)');
DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, exclude_nodata_value boolean, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, quantile double precision)');
DROP FUNCTION IF EXISTS st_quantile(rastertable text, rastercolumn text, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile( rastertable text, rastercolumn text, nband int, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_approxquantile( rastertable text, rastercolumn text, nband int, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile( rastertable text, rastercolumn text, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_approxquantile( rastertable text, rastercolumn text, sample_percent double precision, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile( rastertable text, rastercolumn text, quantiles double precision[], OUT quantile double precision, OUT value double precision)');
DROP FUNCTION IF EXISTS st_approxquantile( rastertable text, rastercolumn text, quantiles double precision[], OUT quantile double precision, OUT value double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, sample_percent double precision, quantile double precision)');
DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, nband int, exclude_nodata_value boolean, sample_percent double precision, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, nband int, sample_percent double precision, quantile double precision)');
DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, nband int, sample_percent double precision, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, sample_percent double precision, quantile double precision)');
DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, sample_percent double precision, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, exclude_nodata_value boolean, quantile double precision)');
DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, exclude_nodata_value boolean, quantile double precision);
SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, quantile double precision)');
DROP FUNCTION IF EXISTS st_approxquantile(rastertable text, rastercolumn text, quantile double precision);

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_value(rast raster, band integer, pt geometry, exclude_nodata_value boolean)');
DROP FUNCTION IF EXISTS st_value(rast raster, band integer, pt geometry, exclude_nodata_value boolean);

SELECT postgis_extension_drop_if_exists('postgis_raster', 'DROP FUNCTION IF EXISTS st_gdalopenoptions(opts text[])');
DROP FUNCTION IF EXISTS st_gdalopenoptions(opts text[]);



COMMENT ON FUNCTION AddRasterConstraints(name , name , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean ) IS 'args: rasttable, rastcolumn, srid=true, scale_x=true, scale_y=true, blocksize_x=true, blocksize_y=true, same_alignment=true, regular_blocking=false, num_bands=true, pixel_types=true, nodata_values=true, out_db=true, extent=true - Adds raster constraints to a loaded raster table for a specific column that constrains spatial ref, scaling, blocksize, alignment, bands, band type and a flag to denote if raster column is regularly blocked. The table must be loaded with data for the constraints to be inferred. Returns true if the constraint setting was accomplished and issues a notice otherwise.';
			
COMMENT ON FUNCTION AddRasterConstraints(name , name , text[] ) IS 'args: rasttable, rastcolumn, VARIADIC constraints - Adds raster constraints to a loaded raster table for a specific column that constrains spatial ref, scaling, blocksize, alignment, bands, band type and a flag to denote if raster column is regularly blocked. The table must be loaded with data for the constraints to be inferred. Returns true if the constraint setting was accomplished and issues a notice otherwise.';
			
COMMENT ON FUNCTION AddRasterConstraints(name , name , name , text[] ) IS 'args: rastschema, rasttable, rastcolumn, VARIADIC constraints - Adds raster constraints to a loaded raster table for a specific column that constrains spatial ref, scaling, blocksize, alignment, bands, band type and a flag to denote if raster column is regularly blocked. The table must be loaded with data for the constraints to be inferred. Returns true if the constraint setting was accomplished and issues a notice otherwise.';
			
COMMENT ON FUNCTION AddRasterConstraints(name , name , name , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean ) IS 'args: rastschema, rasttable, rastcolumn, srid=true, scale_x=true, scale_y=true, blocksize_x=true, blocksize_y=true, same_alignment=true, regular_blocking=false, num_bands=true, pixel_types=true, nodata_values=true, out_db=true, extent=true - Adds raster constraints to a loaded raster table for a specific column that constrains spatial ref, scaling, blocksize, alignment, bands, band type and a flag to denote if raster column is regularly blocked. The table must be loaded with data for the constraints to be inferred. Returns true if the constraint setting was accomplished and issues a notice otherwise.';
			
COMMENT ON FUNCTION DropRasterConstraints(name , name , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean ) IS 'args: rasttable, rastcolumn, srid, scale_x, scale_y, blocksize_x, blocksize_y, same_alignment, regular_blocking, num_bands=true, pixel_types=true, nodata_values=true, out_db=true, extent=true - Drops PostGIS raster constraints that refer to a raster table column. Useful if you need to reload data or update your raster column data.';
			
COMMENT ON FUNCTION DropRasterConstraints(name , name , name , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean , boolean ) IS 'args: rastschema, rasttable, rastcolumn, srid=true, scale_x=true, scale_y=true, blocksize_x=true, blocksize_y=true, same_alignment=true, regular_blocking=false, num_bands=true, pixel_types=true, nodata_values=true, out_db=true, extent=true - Drops PostGIS raster constraints that refer to a raster table column. Useful if you need to reload data or update your raster column data.';
			
COMMENT ON FUNCTION DropRasterConstraints(name , name , name , text[] ) IS 'args: rastschema, rasttable, rastcolumn, constraints - Drops PostGIS raster constraints that refer to a raster table column. Useful if you need to reload data or update your raster column data.';
			
COMMENT ON FUNCTION AddOverviewConstraints(name , name , name , name , name , name , int ) IS 'args: ovschema, ovtable, ovcolumn, refschema, reftable, refcolumn, ovfactor - Tag a raster column as being an overview of another.';
			
COMMENT ON FUNCTION AddOverviewConstraints(name , name , name , name , int ) IS 'args: ovtable, ovcolumn, reftable, refcolumn, ovfactor - Tag a raster column as being an overview of another.';
			
COMMENT ON FUNCTION DropOverviewConstraints(name , name , name ) IS 'args: ovschema, ovtable, ovcolumn - Untag a raster column from being an overview of another.';
			
COMMENT ON FUNCTION DropOverviewConstraints(name , name ) IS 'args: ovtable, ovcolumn - Untag a raster column from being an overview of another.';
			
COMMENT ON FUNCTION PostGIS_GDAL_Version() IS 'Reports the version of the GDAL library in use by PostGIS.';
			
COMMENT ON FUNCTION PostGIS_Raster_Lib_Build_Date() IS 'Reports full raster library build date.';
			
COMMENT ON FUNCTION PostGIS_Raster_Lib_Version() IS 'Reports full raster version and build configuration infos.';
			
COMMENT ON FUNCTION ST_GDALDrivers() IS 'args: OUT idx, OUT short_name, OUT long_name, OUT can_read, OUT can_write, OUT create_options - Returns a list of raster formats supported by PostGIS through GDAL. Only those formats with can_write=True can be used by ST_AsGDALRaster';
			
COMMENT ON FUNCTION ST_Contour(raster , integer , double precision , double precision , double precision[] , boolean ) IS 'args: rast, bandnumber, level_interval, level_base, fixed_levels, polygonize - Generates a set of vector contours from the provided raster band, using the GDAL contouring algorithm.';
			
COMMENT ON FUNCTION ST_InterpolateRaster(geometry , text , raster , integer ) IS 'args: input_points, algorithm_options, template, template_band_num=1 - Interpolates a gridded surface based on an input set of 3-d points, using the X- and Y-values to position the points on the grid and the Z-value of the points as the surface elevation.';
			
COMMENT ON FUNCTION UpdateRasterSRID(name , name , name , integer ) IS 'args: schema_name, table_name, column_name, new_srid - Change the SRID of all rasters in the user-specified column and table.';
			
COMMENT ON FUNCTION UpdateRasterSRID(name , name , integer ) IS 'args: table_name, column_name, new_srid - Change the SRID of all rasters in the user-specified column and table.';
			
COMMENT ON FUNCTION ST_CreateOverview(regclass , name , int , text ) IS 'args: tab, col, factor, algo=''NearestNeighbor'' - Create an reduced resolution version of a given raster coverage.';
			
COMMENT ON FUNCTION ST_AddBand(raster , addbandarg[] ) IS 'args: rast, addbandargset - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AddBand(raster , integer , text , double precision , double precision ) IS 'args: rast, index, pixeltype, initialvalue=0, nodataval=NULL - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AddBand(raster , text , double precision , double precision ) IS 'args: rast, pixeltype, initialvalue=0, nodataval=NULL - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AddBand(raster , raster , integer , integer ) IS 'args: torast, fromrast, fromband=1, torastindex=at_end - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AddBand(raster , raster[] , integer , integer ) IS 'args: torast, fromrasts, fromband=1, torastindex=at_end - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AddBand(raster , integer , text , integer[] , double precision ) IS 'args: rast, index, outdbfile, outdbindex, nodataval=NULL - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AddBand(raster , text , integer[] , integer , double precision ) IS 'args: rast, outdbfile, outdbindex, index=at_end, nodataval=NULL - Returns a raster with the new band(s) of given type added with given initial value in the given index location. If no index is specified, the band is added to the end.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , raster , text , double precision , double precision , boolean ) IS 'args: geom, ref, pixeltype, value=1, nodataval=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , raster , text[] , double precision[] , double precision[] , boolean ) IS 'args: geom, ref, pixeltype=ARRAY[''8BUI''], value=ARRAY[1], nodataval=ARRAY[0], touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , double precision , double precision , double precision , double precision , text , double precision , double precision , double precision , double precision , boolean ) IS 'args: geom, scalex, scaley, gridx, gridy, pixeltype, value=1, nodataval=0, skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , double precision , double precision , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision , boolean ) IS 'args: geom, scalex, scaley, gridx=NULL, gridy=NULL, pixeltype=ARRAY[''8BUI''], value=ARRAY[1], nodataval=ARRAY[0], skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , double precision , double precision , text , double precision , double precision , double precision , double precision , double precision , double precision , boolean ) IS 'args: geom, scalex, scaley, pixeltype, value=1, nodataval=0, upperleftx=NULL, upperlefty=NULL, skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision , double precision , double precision , boolean ) IS 'args: geom, scalex, scaley, pixeltype, value=ARRAY[1], nodataval=ARRAY[0], upperleftx=NULL, upperlefty=NULL, skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , integer , integer , double precision , double precision , text , double precision , double precision , double precision , double precision , boolean ) IS 'args: geom, width, height, gridx, gridy, pixeltype, value=1, nodataval=0, skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , integer , integer , double precision , double precision , text[] , double precision[] , double precision[] , double precision , double precision , boolean ) IS 'args: geom, width, height, gridx=NULL, gridy=NULL, pixeltype=ARRAY[''8BUI''], value=ARRAY[1], nodataval=ARRAY[0], skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , integer , integer , text , double precision , double precision , double precision , double precision , double precision , double precision , boolean ) IS 'args: geom, width, height, pixeltype, value=1, nodataval=0, upperleftx=NULL, upperlefty=NULL, skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_AsRaster(geometry , integer , integer , text[] , double precision[] , double precision[] , double precision , double precision , double precision , double precision , boolean ) IS 'args: geom, width, height, pixeltype, value=ARRAY[1], nodataval=ARRAY[0], upperleftx=NULL, upperlefty=NULL, skewx=0, skewy=0, touched=false - Converts a PostGIS geometry to a PostGIS raster.';
			
COMMENT ON FUNCTION ST_Band(raster , integer[] ) IS 'args: rast, nbands = ARRAY[1] - Returns one or more bands of an existing raster as a new raster. Useful for building new rasters from existing rasters.';
			
COMMENT ON FUNCTION ST_Band(raster , integer ) IS 'args: rast, nband - Returns one or more bands of an existing raster as a new raster. Useful for building new rasters from existing rasters.';
			
COMMENT ON FUNCTION ST_Band(raster , text , character ) IS 'args: rast, nbands, delimiter=, - Returns one or more bands of an existing raster as a new raster. Useful for building new rasters from existing rasters.';
			
COMMENT ON FUNCTION ST_MakeEmptyCoverage(integer , integer , integer , integer , double precision , double precision , double precision , double precision , double precision , double precision , integer ) IS 'args: tilewidth, tileheight, width, height, upperleftx, upperlefty, scalex, scaley, skewx, skewy, srid=unknown - Cover georeferenced area with a grid of empty raster tiles.';
			
COMMENT ON FUNCTION ST_MakeEmptyRaster(raster ) IS 'args: rast - Returns an empty raster (having no bands) of given dimensions (width & height), upperleft X and Y, pixel size and rotation (scalex, scaley, skewx & skewy) and reference system (srid). If a raster is passed in, returns a new raster with the same size, alignment and SRID. If srid is left out, the spatial ref is set to unknown (0).';
			
COMMENT ON FUNCTION ST_MakeEmptyRaster(integer , integer , float8 , float8 , float8 , float8 , float8 , float8 , integer ) IS 'args: width, height, upperleftx, upperlefty, scalex, scaley, skewx, skewy, srid=unknown - Returns an empty raster (having no bands) of given dimensions (width & height), upperleft X and Y, pixel size and rotation (scalex, scaley, skewx & skewy) and reference system (srid). If a raster is passed in, returns a new raster with the same size, alignment and SRID. If srid is left out, the spatial ref is set to unknown (0).';
			
COMMENT ON FUNCTION ST_MakeEmptyRaster(integer , integer , float8  , float8  , float8  ) IS 'args: width, height, upperleftx, upperlefty, pixelsize - Returns an empty raster (having no bands) of given dimensions (width & height), upperleft X and Y, pixel size and rotation (scalex, scaley, skewx & skewy) and reference system (srid). If a raster is passed in, returns a new raster with the same size, alignment and SRID. If srid is left out, the spatial ref is set to unknown (0).';
			
COMMENT ON FUNCTION ST_Tile(raster , int[] , integer , integer , boolean , double precision ) IS 'args: rast, nband, width, height, padwithnodata=FALSE, nodataval=NULL - Returns a set of rasters resulting from the split of the input raster based upon the desired dimensions of the output rasters.';
			
COMMENT ON FUNCTION ST_Tile(raster , integer , integer , integer , boolean , double precision ) IS 'args: rast, nband, width, height, padwithnodata=FALSE, nodataval=NULL - Returns a set of rasters resulting from the split of the input raster based upon the desired dimensions of the output rasters.';
			
COMMENT ON FUNCTION ST_Tile(raster , integer , integer , boolean , double precision ) IS 'args: rast, width, height, padwithnodata=FALSE, nodataval=NULL - Returns a set of rasters resulting from the split of the input raster based upon the desired dimensions of the output rasters.';
			
COMMENT ON FUNCTION ST_Retile(regclass , name , geometry , float8 , float8 , int , int , text ) IS 'args: tab, col, ext, sfx, sfy, tw, th, algo=''NearestNeighbor'' - Return a set of configured tiles from an arbitrarily tiled raster coverage.';
			
COMMENT ON FUNCTION ST_FromGDALRaster(bytea , integer ) IS 'args: gdaldata, srid=NULL - Returns a raster from a supported GDAL raster file.';
			
COMMENT ON FUNCTION ST_GeoReference(raster , text ) IS 'args: rast, format=GDAL - Returns the georeference meta data in GDAL or ESRI format as commonly seen in a world file. Default is GDAL.';
			
COMMENT ON FUNCTION ST_Height(raster ) IS 'args: rast - Returns the height of the raster in pixels.';
			
COMMENT ON FUNCTION ST_IsEmpty(raster ) IS 'args: rast - Returns true if the raster is empty (width = 0 and height = 0). Otherwise, returns false.';
			
COMMENT ON FUNCTION ST_MemSize(raster ) IS 'args: rast - Returns the amount of space (in bytes) the raster takes.';
			
COMMENT ON FUNCTION ST_MetaData(raster ) IS 'args: rast - Returns basic meta data about a raster object such as pixel size, rotation (skew), upper, lower left, etc.';
			
COMMENT ON FUNCTION ST_NumBands(raster ) IS 'args: rast - Returns the number of bands in the raster object.';
			
COMMENT ON FUNCTION ST_PixelHeight(raster ) IS 'args: rast - Returns the pixel height in geometric units of the spatial reference system.';
			
COMMENT ON FUNCTION ST_PixelWidth(raster ) IS 'args: rast - Returns the pixel width in geometric units of the spatial reference system.';
			
COMMENT ON FUNCTION ST_ScaleX(raster ) IS 'args: rast - Returns the X component of the pixel width in units of coordinate reference system.';
			
COMMENT ON FUNCTION ST_ScaleY(raster ) IS 'args: rast - Returns the Y component of the pixel height in units of coordinate reference system.';
			
COMMENT ON FUNCTION ST_RasterToWorldCoord(raster , integer , integer ) IS 'args: rast, xcolumn, yrow - Returns the rasters upper left corner as geometric X and Y (longitude and latitude) given a column and row. Column and row starts at 1.';
			
COMMENT ON FUNCTION ST_RasterToWorldCoordX(raster , integer ) IS 'args: rast, xcolumn - Returns the geometric X coordinate upper left of a raster, column and row. Numbering of columns and rows starts at 1.';
			
COMMENT ON FUNCTION ST_RasterToWorldCoordX(raster , integer , integer ) IS 'args: rast, xcolumn, yrow - Returns the geometric X coordinate upper left of a raster, column and row. Numbering of columns and rows starts at 1.';
			
COMMENT ON FUNCTION ST_RasterToWorldCoordY(raster , integer ) IS 'args: rast, yrow - Returns the geometric Y coordinate upper left corner of a raster, column and row. Numbering of columns and rows starts at 1.';
			
COMMENT ON FUNCTION ST_RasterToWorldCoordY(raster , integer , integer ) IS 'args: rast, xcolumn, yrow - Returns the geometric Y coordinate upper left corner of a raster, column and row. Numbering of columns and rows starts at 1.';
			
COMMENT ON FUNCTION ST_Rotation(raster) IS 'args: rast - Returns the rotation of the raster in radian.';
			
COMMENT ON FUNCTION ST_SkewX(raster ) IS 'args: rast - Returns the georeference X skew (or rotation parameter).';
			
COMMENT ON FUNCTION ST_SkewY(raster ) IS 'args: rast - Returns the georeference Y skew (or rotation parameter).';
			
COMMENT ON FUNCTION ST_SRID(raster ) IS 'args: rast - Returns the spatial reference identifier of the raster as defined in spatial_ref_sys table.';
			
COMMENT ON FUNCTION ST_Summary(raster ) IS 'args: rast - Returns a text summary of the contents of the raster.';
			
COMMENT ON FUNCTION ST_UpperLeftX(raster ) IS 'args: rast - Returns the upper left X coordinate of raster in projected spatial ref.';
			
COMMENT ON FUNCTION ST_UpperLeftY(raster ) IS 'args: rast - Returns the upper left Y coordinate of raster in projected spatial ref.';
			
COMMENT ON FUNCTION ST_Width(raster ) IS 'args: rast - Returns the width of the raster in pixels.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoord(raster , geometry ) IS 'args: rast, pt - Returns the upper left corner as column and row given geometric X and Y (longitude and latitude) or a point geometry expressed in the spatial reference coordinate system of the raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoord(raster , double precision , double precision ) IS 'args: rast, longitude, latitude - Returns the upper left corner as column and row given geometric X and Y (longitude and latitude) or a point geometry expressed in the spatial reference coordinate system of the raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoordX(raster , geometry ) IS 'args: rast, pt - Returns the column in the raster of the point geometry (pt) or a X and Y world coordinate (xw, yw) represented in world spatial reference system of raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoordX(raster , double precision ) IS 'args: rast, xw - Returns the column in the raster of the point geometry (pt) or a X and Y world coordinate (xw, yw) represented in world spatial reference system of raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoordX(raster , double precision , double precision ) IS 'args: rast, xw, yw - Returns the column in the raster of the point geometry (pt) or a X and Y world coordinate (xw, yw) represented in world spatial reference system of raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoordY(raster , geometry ) IS 'args: rast, pt - Returns the row in the raster of the point geometry (pt) or a X and Y world coordinate (xw, yw) represented in world spatial reference system of raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoordY(raster , double precision ) IS 'args: rast, xw - Returns the row in the raster of the point geometry (pt) or a X and Y world coordinate (xw, yw) represented in world spatial reference system of raster.';
			
COMMENT ON FUNCTION ST_WorldToRasterCoordY(raster , double precision , double precision ) IS 'args: rast, xw, yw - Returns the row in the raster of the point geometry (pt) or a X and Y world coordinate (xw, yw) represented in world spatial reference system of raster.';
			
COMMENT ON FUNCTION ST_BandMetaData(raster , integer ) IS 'args: rast, band=1 - Returns basic meta data for a specific raster band. band num 1 is assumed if none-specified.';
			
COMMENT ON FUNCTION ST_BandMetaData(raster , integer[] ) IS 'args: rast, band - Returns basic meta data for a specific raster band. band num 1 is assumed if none-specified.';
			
COMMENT ON FUNCTION ST_BandNoDataValue(raster , integer ) IS 'args: rast, bandnum=1 - Returns the value in a given band that represents no data. If no band num 1 is assumed.';
			
COMMENT ON FUNCTION ST_BandIsNoData(raster , integer , boolean ) IS 'args: rast, band, forceChecking=true - Returns true if the band is filled with only nodata values.';
			
COMMENT ON FUNCTION ST_BandIsNoData(raster , boolean ) IS 'args: rast, forceChecking=true - Returns true if the band is filled with only nodata values.';
			
COMMENT ON FUNCTION ST_BandPath(raster , integer ) IS 'args: rast, bandnum=1 - Returns system file path to a band stored in file system. If no bandnum specified, 1 is assumed.';
			
COMMENT ON FUNCTION ST_BandFileSize(raster , integer ) IS 'args: rast, bandnum=1 - Returns the file size of a band stored in file system. If no bandnum specified, 1 is assumed.';
			
COMMENT ON FUNCTION ST_BandFileTimestamp(raster , integer ) IS 'args: rast, bandnum=1 - Returns the file timestamp of a band stored in file system. If no bandnum specified, 1 is assumed.';
			
COMMENT ON FUNCTION ST_BandPixelType(raster , integer ) IS 'args: rast, bandnum=1 - Returns the type of pixel for given band. If no bandnum specified, 1 is assumed.';
			
COMMENT ON FUNCTION ST_MinPossibleValue(text ) IS 'args: pixeltype - Returns the minimum value this pixeltype can store.';
			
COMMENT ON FUNCTION ST_HasNoBand(raster , integer ) IS 'args: rast, bandnum=1 - Returns true if there is no band with given band number. If no band number is specified, then band number 1 is assumed.';
			
COMMENT ON FUNCTION ST_PixelAsPolygon(raster , integer , integer ) IS 'args: rast, columnx, rowy - Returns the polygon geometry that bounds the pixel for a particular row and column.';
			
COMMENT ON FUNCTION ST_PixelAsPolygons(raster , integer , boolean ) IS 'args: rast, band=1, exclude_nodata_value=TRUE - Returns the polygon geometry that bounds every pixel of a raster band along with the value, the X and the Y raster coordinates of each pixel.';
			
COMMENT ON FUNCTION ST_PixelAsPoint(raster , integer , integer ) IS 'args: rast, columnx, rowy - Returns a point geometry of the pixels upper-left corner.';
			
COMMENT ON FUNCTION ST_PixelAsPoints(raster , integer , boolean ) IS 'args: rast, band=1, exclude_nodata_value=TRUE - Returns a point geometry for each pixel of a raster band along with the value, the X and the Y raster coordinates of each pixel. The coordinates of the point geometry are of the pixels upper-left corner.';
			
COMMENT ON FUNCTION ST_PixelAsCentroid(raster , integer , integer ) IS 'args: rast, x, y - Returns the centroid (point geometry) of the area represented by a pixel.';
			
COMMENT ON FUNCTION ST_PixelAsCentroids(raster , integer , boolean ) IS 'args: rast, band=1, exclude_nodata_value=TRUE - Returns the centroid (point geometry) for each pixel of a raster band along with the value, the X and the Y raster coordinates of each pixel. The point geometry is the centroid of the area represented by a pixel.';
			
COMMENT ON FUNCTION ST_Value(raster , geometry , boolean ) IS 'args: rast, pt, exclude_nodata_value=true - Returns the value of a given band in a given columnx, rowy pixel or at a particular geometric point. Band numbers start at 1 and assumed to be 1 if not specified. If exclude_nodata_value is set to false, then all pixels include nodata pixels are considered to intersect and return value. If exclude_nodata_value is not passed in then reads it from metadata of raster.';
			
COMMENT ON FUNCTION ST_Value(raster , integer , geometry , boolean , text ) IS 'args: rast, band, pt, exclude_nodata_value=true, resample=''nearest'' - Returns the value of a given band in a given columnx, rowy pixel or at a particular geometric point. Band numbers start at 1 and assumed to be 1 if not specified. If exclude_nodata_value is set to false, then all pixels include nodata pixels are considered to intersect and return value. If exclude_nodata_value is not passed in then reads it from metadata of raster.';
			
COMMENT ON FUNCTION ST_Value(raster , integer , integer , boolean ) IS 'args: rast, x, y, exclude_nodata_value=true - Returns the value of a given band in a given columnx, rowy pixel or at a particular geometric point. Band numbers start at 1 and assumed to be 1 if not specified. If exclude_nodata_value is set to false, then all pixels include nodata pixels are considered to intersect and return value. If exclude_nodata_value is not passed in then reads it from metadata of raster.';
			
COMMENT ON FUNCTION ST_Value(raster , integer , integer , integer , boolean ) IS 'args: rast, band, x, y, exclude_nodata_value=true - Returns the value of a given band in a given columnx, rowy pixel or at a particular geometric point. Band numbers start at 1 and assumed to be 1 if not specified. If exclude_nodata_value is set to false, then all pixels include nodata pixels are considered to intersect and return value. If exclude_nodata_value is not passed in then reads it from metadata of raster.';
			
COMMENT ON FUNCTION ST_NearestValue(raster , integer , geometry , boolean ) IS 'args: rast, bandnum, pt, exclude_nodata_value=true - Returns the nearest non-NODATA value of a given bands pixel specified by a columnx and rowy or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_NearestValue(raster , geometry , boolean ) IS 'args: rast, pt, exclude_nodata_value=true - Returns the nearest non-NODATA value of a given bands pixel specified by a columnx and rowy or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_NearestValue(raster , integer , integer , integer , boolean ) IS 'args: rast, bandnum, columnx, rowy, exclude_nodata_value=true - Returns the nearest non-NODATA value of a given bands pixel specified by a columnx and rowy or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_NearestValue(raster , integer , integer , boolean ) IS 'args: rast, columnx, rowy, exclude_nodata_value=true - Returns the nearest non-NODATA value of a given bands pixel specified by a columnx and rowy or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_SetZ(raster , geometry , text , integer ) IS 'args: rast, geom, resample=nearest, band=1 - Returns a geometry with the same X/Y coordinates as the input geometry, and values from the raster copied into the Z dimension using the requested resample algorithm.';
			
COMMENT ON FUNCTION ST_SetM(raster , geometry , text , integer ) IS 'args: rast, geom, resample=nearest, band=1 - Returns a geometry with the same X/Y coordinates as the input geometry, and values from the raster copied into the Z dimension using the requested resample algorithm.';
			
COMMENT ON FUNCTION ST_Neighborhood(raster , integer , integer , integer , integer , integer , boolean ) IS 'args: rast, bandnum, columnX, rowY, distanceX, distanceY, exclude_nodata_value=true - Returns a 2-D double precision array of the non-NODATA values around a given bands pixel specified by either a columnX and rowY or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_Neighborhood(raster , integer , integer , integer , integer , boolean ) IS 'args: rast, columnX, rowY, distanceX, distanceY, exclude_nodata_value=true - Returns a 2-D double precision array of the non-NODATA values around a given bands pixel specified by either a columnX and rowY or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_Neighborhood(raster , integer , geometry , integer , integer , boolean ) IS 'args: rast, bandnum, pt, distanceX, distanceY, exclude_nodata_value=true - Returns a 2-D double precision array of the non-NODATA values around a given bands pixel specified by either a columnX and rowY or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_Neighborhood(raster , geometry , integer , integer , boolean ) IS 'args: rast, pt, distanceX, distanceY, exclude_nodata_value=true - Returns a 2-D double precision array of the non-NODATA values around a given bands pixel specified by either a columnX and rowY or a geometric point expressed in the same spatial reference coordinate system as the raster.';
			
COMMENT ON FUNCTION ST_SetValue(raster , integer , geometry , double precision ) IS 'args: rast, bandnum, geom, newvalue - Returns modified raster resulting from setting the value of a given band in a given columnx, rowy pixel or the pixels that intersect a particular geometry. Band numbers start at 1 and assumed to be 1 if not specified.';
			
COMMENT ON FUNCTION ST_SetValue(raster , geometry , double precision ) IS 'args: rast, geom, newvalue - Returns modified raster resulting from setting the value of a given band in a given columnx, rowy pixel or the pixels that intersect a particular geometry. Band numbers start at 1 and assumed to be 1 if not specified.';
			
COMMENT ON FUNCTION ST_SetValue(raster , integer , integer , integer , double precision ) IS 'args: rast, bandnum, columnx, rowy, newvalue - Returns modified raster resulting from setting the value of a given band in a given columnx, rowy pixel or the pixels that intersect a particular geometry. Band numbers start at 1 and assumed to be 1 if not specified.';
			
COMMENT ON FUNCTION ST_SetValue(raster , integer , integer , double precision ) IS 'args: rast, columnx, rowy, newvalue - Returns modified raster resulting from setting the value of a given band in a given columnx, rowy pixel or the pixels that intersect a particular geometry. Band numbers start at 1 and assumed to be 1 if not specified.';
			
COMMENT ON FUNCTION ST_SetValues(raster , integer , integer , integer , double precision[][] , boolean[][] , boolean ) IS 'args: rast, nband, columnx, rowy, newvalueset, noset=NULL, keepnodata=FALSE - Returns modified raster resulting from setting the values of a given band.';
			
COMMENT ON FUNCTION ST_SetValues(raster , integer , integer , integer , double precision[][] , double precision , boolean ) IS 'args: rast, nband, columnx, rowy, newvalueset, nosetvalue, keepnodata=FALSE - Returns modified raster resulting from setting the values of a given band.';
			
COMMENT ON FUNCTION ST_SetValues(raster , integer , integer , integer , integer , integer , double precision , boolean ) IS 'args: rast, nband, columnx, rowy, width, height, newvalue, keepnodata=FALSE - Returns modified raster resulting from setting the values of a given band.';
			
COMMENT ON FUNCTION ST_SetValues(raster , integer , integer , integer , integer , double precision , boolean ) IS 'args: rast, columnx, rowy, width, height, newvalue, keepnodata=FALSE - Returns modified raster resulting from setting the values of a given band.';
			
COMMENT ON FUNCTION ST_SetValues(raster , integer , geomval[] , boolean ) IS 'args: rast, nband, geomvalset, keepnodata=FALSE - Returns modified raster resulting from setting the values of a given band.';
			
COMMENT ON FUNCTION ST_DumpValues(raster , integer[] , boolean ) IS 'args: rast, nband=NULL, exclude_nodata_value=true - Get the values of the specified band as a 2-dimension array.';
			
COMMENT ON FUNCTION ST_DumpValues(raster , integer , boolean ) IS 'args: rast, nband, exclude_nodata_value=true - Get the values of the specified band as a 2-dimension array.';
			
COMMENT ON FUNCTION ST_PixelOfValue(raster , integer , double precision[] , boolean ) IS 'args: rast, nband, search, exclude_nodata_value=true - Get the columnx, rowy coordinates of the pixel whose value equals the search value.';
			
COMMENT ON FUNCTION ST_PixelOfValue(raster , double precision[] , boolean ) IS 'args: rast, search, exclude_nodata_value=true - Get the columnx, rowy coordinates of the pixel whose value equals the search value.';
			
COMMENT ON FUNCTION ST_PixelOfValue(raster , integer , double precision , boolean ) IS 'args: rast, nband, search, exclude_nodata_value=true - Get the columnx, rowy coordinates of the pixel whose value equals the search value.';
			
COMMENT ON FUNCTION ST_PixelOfValue(raster , double precision , boolean ) IS 'args: rast, search, exclude_nodata_value=true - Get the columnx, rowy coordinates of the pixel whose value equals the search value.';
			
COMMENT ON FUNCTION ST_SetGeoReference(raster , text , text ) IS 'args: rast, georefcoords, format=GDAL - Set Georeference 6 georeference parameters in a single call. Numbers should be separated by white space. Accepts inputs in GDAL or ESRI format. Default is GDAL.';
			
COMMENT ON FUNCTION ST_SetGeoReference(raster , double precision , double precision , double precision , double precision , double precision , double precision ) IS 'args: rast, upperleftx, upperlefty, scalex, scaley, skewx, skewy - Set Georeference 6 georeference parameters in a single call. Numbers should be separated by white space. Accepts inputs in GDAL or ESRI format. Default is GDAL.';
			
COMMENT ON FUNCTION ST_SetRotation(raster, float8) IS 'args: rast, rotation - Set the rotation of the raster in radian.';
			
COMMENT ON FUNCTION ST_SetScale(raster , float8 ) IS 'args: rast, xy - Sets the X and Y size of pixels in units of coordinate reference system. Number units/pixel width/height.';
			
COMMENT ON FUNCTION ST_SetScale(raster , float8 , float8 ) IS 'args: rast, x, y - Sets the X and Y size of pixels in units of coordinate reference system. Number units/pixel width/height.';
			
COMMENT ON FUNCTION ST_SetSkew(raster , float8 ) IS 'args: rast, skewxy - Sets the georeference X and Y skew (or rotation parameter). If only one is passed in, sets X and Y to the same value.';
			
COMMENT ON FUNCTION ST_SetSkew(raster , float8 , float8 ) IS 'args: rast, skewx, skewy - Sets the georeference X and Y skew (or rotation parameter). If only one is passed in, sets X and Y to the same value.';
			
COMMENT ON FUNCTION ST_SetSRID(raster , integer ) IS 'args: rast, srid - Sets the SRID of a raster to a particular integer srid defined in the spatial_ref_sys table.';
			
COMMENT ON FUNCTION ST_SetUpperLeft(raster , double precision , double precision ) IS 'args: rast, x, y - Sets the value of the upper left corner of the pixel of the raster to projected X and Y coordinates.';
			
COMMENT ON FUNCTION ST_Resample(raster , integer , integer , double precision , double precision , double precision , double precision , text , double precision ) IS 'args: rast, width, height, gridx=NULL, gridy=NULL, skewx=0, skewy=0, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster using a specified resampling algorithm, new dimensions, an arbitrary grid corner and a set of raster georeferencing attributes defined or borrowed from another raster.';
			
COMMENT ON FUNCTION ST_Resample(raster , double precision , double precision , double precision , double precision , double precision , double precision , text , double precision ) IS 'args: rast, scalex=0, scaley=0, gridx=NULL, gridy=NULL, skewx=0, skewy=0, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster using a specified resampling algorithm, new dimensions, an arbitrary grid corner and a set of raster georeferencing attributes defined or borrowed from another raster.';
			
COMMENT ON FUNCTION ST_Resample(raster , raster , text , double precision , boolean ) IS 'args: rast, ref, algorithm=NearestNeighbor, maxerr=0.125, usescale=true - Resample a raster using a specified resampling algorithm, new dimensions, an arbitrary grid corner and a set of raster georeferencing attributes defined or borrowed from another raster.';
			
COMMENT ON FUNCTION ST_Resample(raster , raster , boolean , text , double precision ) IS 'args: rast, ref, usescale, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster using a specified resampling algorithm, new dimensions, an arbitrary grid corner and a set of raster georeferencing attributes defined or borrowed from another raster.';
			
COMMENT ON FUNCTION ST_Rescale(raster , double precision , text , double precision ) IS 'args: rast, scalexy, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster by adjusting only its scale (or pixel size). New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_Rescale(raster , double precision , double precision , text , double precision ) IS 'args: rast, scalex, scaley, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster by adjusting only its scale (or pixel size). New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_Reskew(raster , double precision , text , double precision ) IS 'args: rast, skewxy, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster by adjusting only its skew (or rotation parameters). New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_Reskew(raster , double precision , double precision , text , double precision ) IS 'args: rast, skewx, skewy, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster by adjusting only its skew (or rotation parameters). New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_SnapToGrid(raster , double precision , double precision , text , double precision , double precision , double precision ) IS 'args: rast, gridx, gridy, algorithm=NearestNeighbor, maxerr=0.125, scalex=DEFAULT 0, scaley=DEFAULT 0 - Resample a raster by snapping it to a grid. New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_SnapToGrid(raster , double precision , double precision , double precision , double precision , text , double precision ) IS 'args: rast, gridx, gridy, scalex, scaley, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster by snapping it to a grid. New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_SnapToGrid(raster , double precision , double precision , double precision , text , double precision ) IS 'args: rast, gridx, gridy, scalexy, algorithm=NearestNeighbor, maxerr=0.125 - Resample a raster by snapping it to a grid. New pixel values are computed using the NearestNeighbor (english or american spelling), Bilinear, Cubic, CubicSpline or Lanczos resampling algorithm. Default is NearestNeighbor.';
			
COMMENT ON FUNCTION ST_Resize(raster , integer , integer , text , double precision ) IS 'args: rast, width, height, algorithm=NearestNeighbor, maxerr=0.125 - Resize a raster to a new width/height';
			
COMMENT ON FUNCTION ST_Resize(raster , double precision , double precision , text , double precision ) IS 'args: rast, percentwidth, percentheight, algorithm=NearestNeighbor, maxerr=0.125 - Resize a raster to a new width/height';
			
COMMENT ON FUNCTION ST_Resize(raster , text , text , text , double precision ) IS 'args: rast, width, height, algorithm=NearestNeighbor, maxerr=0.125 - Resize a raster to a new width/height';
			
COMMENT ON FUNCTION ST_Transform(raster , integer , text , double precision , double precision , double precision ) IS 'args: rast, srid, algorithm=NearestNeighbor, maxerr=0.125, scalex, scaley - Reprojects a raster in a known spatial reference system to another known spatial reference system using specified resampling algorithm. Options are NearestNeighbor, Bilinear, Cubic, CubicSpline, Lanczos defaulting to NearestNeighbor.';
			
COMMENT ON FUNCTION ST_Transform(raster , integer , double precision , double precision , text , double precision ) IS 'args: rast, srid, scalex, scaley, algorithm=NearestNeighbor, maxerr=0.125 - Reprojects a raster in a known spatial reference system to another known spatial reference system using specified resampling algorithm. Options are NearestNeighbor, Bilinear, Cubic, CubicSpline, Lanczos defaulting to NearestNeighbor.';
			
COMMENT ON FUNCTION ST_Transform(raster , raster , text , double precision ) IS 'args: rast, alignto, algorithm=NearestNeighbor, maxerr=0.125 - Reprojects a raster in a known spatial reference system to another known spatial reference system using specified resampling algorithm. Options are NearestNeighbor, Bilinear, Cubic, CubicSpline, Lanczos defaulting to NearestNeighbor.';
			
COMMENT ON FUNCTION ST_SetBandNoDataValue(raster , double precision ) IS 'args: rast, nodatavalue - Sets the value for the given band that represents no data. Band 1 is assumed if no band is specified. To mark a band as having no nodata value, set the nodata value = NULL.';
			
COMMENT ON FUNCTION ST_SetBandNoDataValue(raster , integer , double precision , boolean ) IS 'args: rast, band, nodatavalue, forcechecking=false - Sets the value for the given band that represents no data. Band 1 is assumed if no band is specified. To mark a band as having no nodata value, set the nodata value = NULL.';
			
COMMENT ON FUNCTION ST_SetBandIsNoData(raster , integer ) IS 'args: rast, band=1 - Sets the isnodata flag of the band to TRUE.';
			
COMMENT ON FUNCTION ST_SetBandPath(raster , integer , text , integer , boolean ) IS 'args: rast, band, outdbpath, outdbindex, force=false - Update the external path and band number of an out-db band';
			
COMMENT ON FUNCTION ST_SetBandIndex(raster , integer , integer , boolean ) IS 'args: rast, band, outdbindex, force=false - Update the external band number of an out-db band';
			
COMMENT ON FUNCTION ST_Count(raster , integer , boolean ) IS 'args: rast, nband=1, exclude_nodata_value=true - Returns the number of pixels in a given band of a raster or raster coverage. If no band is specified defaults to band 1. If exclude_nodata_value is set to true, will only count pixels that are not equal to the nodata value.';
			
COMMENT ON FUNCTION ST_Count(raster , boolean ) IS 'args: rast, exclude_nodata_value - Returns the number of pixels in a given band of a raster or raster coverage. If no band is specified defaults to band 1. If exclude_nodata_value is set to true, will only count pixels that are not equal to the nodata value.';
			
COMMENT ON FUNCTION ST_CountAgg(raster , integer , boolean , double precision ) IS 'args: rast, nband, exclude_nodata_value, sample_percent - Aggregate. Returns the number of pixels in a given band of a set of rasters. If no band is specified defaults to band 1. If exclude_nodata_value is set to true, will only count pixels that are not equal to the NODATA value.';
			
COMMENT ON FUNCTION ST_CountAgg(raster , integer , boolean ) IS 'args: rast, nband, exclude_nodata_value - Aggregate. Returns the number of pixels in a given band of a set of rasters. If no band is specified defaults to band 1. If exclude_nodata_value is set to true, will only count pixels that are not equal to the NODATA value.';
			
COMMENT ON FUNCTION ST_CountAgg(raster , boolean ) IS 'args: rast, exclude_nodata_value - Aggregate. Returns the number of pixels in a given band of a set of rasters. If no band is specified defaults to band 1. If exclude_nodata_value is set to true, will only count pixels that are not equal to the NODATA value.';
			
COMMENT ON FUNCTION ST_Histogram(raster , integer , boolean , integer , double precision[] , boolean ) IS 'args: rast, nband=1, exclude_nodata_value=true, bins=autocomputed, width=NULL, right=false - Returns a set of record summarizing a raster or raster coverage data distribution separate bin ranges. Number of bins are autocomputed if not specified.';
			
COMMENT ON FUNCTION ST_Histogram(raster , integer , integer , double precision[] , boolean ) IS 'args: rast, nband, bins, width=NULL, right=false - Returns a set of record summarizing a raster or raster coverage data distribution separate bin ranges. Number of bins are autocomputed if not specified.';
			
COMMENT ON FUNCTION ST_Histogram(raster , integer , boolean , integer , boolean ) IS 'args: rast, nband, exclude_nodata_value, bins, right - Returns a set of record summarizing a raster or raster coverage data distribution separate bin ranges. Number of bins are autocomputed if not specified.';
			
COMMENT ON FUNCTION ST_Histogram(raster , integer , integer , boolean ) IS 'args: rast, nband, bins, right - Returns a set of record summarizing a raster or raster coverage data distribution separate bin ranges. Number of bins are autocomputed if not specified.';
			
COMMENT ON FUNCTION ST_Quantile(raster , integer , boolean , double precision[] ) IS 'args: rast, nband=1, exclude_nodata_value=true, quantiles=NULL - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , double precision[] ) IS 'args: rast, quantiles - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , integer , double precision[] ) IS 'args: rast, nband, quantiles - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , double precision ) IS 'args: rast, quantile - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , boolean , double precision ) IS 'args: rast, exclude_nodata_value, quantile=NULL - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , integer , double precision ) IS 'args: rast, nband, quantile - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , integer , boolean , double precision ) IS 'args: rast, nband, exclude_nodata_value, quantile - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_Quantile(raster , integer , double precision ) IS 'args: rast, nband, quantile - Compute quantiles for a raster or raster table coverage in the context of the sample or population. Thus, a value could be examined to be at the rasters 25%, 50%, 75% percentile.';
			
COMMENT ON FUNCTION ST_SummaryStats(raster , boolean ) IS 'args: rast, exclude_nodata_value - Returns summarystats consisting of count, sum, mean, stddev, min, max for a given raster band of a raster or raster coverage. Band 1 is assumed is no band is specified.';
			
COMMENT ON FUNCTION ST_SummaryStats(raster , integer , boolean ) IS 'args: rast, nband, exclude_nodata_value - Returns summarystats consisting of count, sum, mean, stddev, min, max for a given raster band of a raster or raster coverage. Band 1 is assumed is no band is specified.';
			
COMMENT ON FUNCTION ST_SummaryStatsAgg(raster , integer , boolean , double precision ) IS 'args: rast, nband, exclude_nodata_value, sample_percent - Aggregate. Returns summarystats consisting of count, sum, mean, stddev, min, max for a given raster band of a set of raster. Band 1 is assumed is no band is specified.';
			
COMMENT ON FUNCTION ST_SummaryStatsAgg(raster , boolean , double precision ) IS 'args: rast, exclude_nodata_value, sample_percent - Aggregate. Returns summarystats consisting of count, sum, mean, stddev, min, max for a given raster band of a set of raster. Band 1 is assumed is no band is specified.';
			
COMMENT ON FUNCTION ST_SummaryStatsAgg(raster , integer , boolean ) IS 'args: rast, nband, exclude_nodata_value - Aggregate. Returns summarystats consisting of count, sum, mean, stddev, min, max for a given raster band of a set of raster. Band 1 is assumed is no band is specified.';
			
COMMENT ON FUNCTION ST_ValueCount(raster , integer , boolean , double precision[] , double precision ) IS 'args: rast, nband=1, exclude_nodata_value=true, searchvalues=NULL, roundto=0, OUT value, OUT count - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(raster , integer , double precision[] , double precision ) IS 'args: rast, nband, searchvalues, roundto=0, OUT value, OUT count - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(raster , double precision[] , double precision ) IS 'args: rast, searchvalues, roundto=0, OUT value, OUT count - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(raster , double precision , double precision ) IS 'args: rast, searchvalue, roundto=0 - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(raster , integer , boolean , double precision , double precision ) IS 'args: rast, nband, exclude_nodata_value, searchvalue, roundto=0 - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(raster , integer , double precision , double precision ) IS 'args: rast, nband, searchvalue, roundto=0 - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(text , text , integer , boolean , double precision[] , double precision ) IS 'args: rastertable, rastercolumn, nband=1, exclude_nodata_value=true, searchvalues=NULL, roundto=0, OUT value, OUT count - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(text , text , double precision[] , double precision ) IS 'args: rastertable, rastercolumn, searchvalues, roundto=0, OUT value, OUT count - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(text , text , integer , double precision[] , double precision ) IS 'args: rastertable, rastercolumn, nband, searchvalues, roundto=0, OUT value, OUT count - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(text , text , integer , boolean , double precision , double precision ) IS 'args: rastertable, rastercolumn, nband, exclude_nodata_value, searchvalue, roundto=0 - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(text , text , double precision , double precision ) IS 'args: rastertable, rastercolumn, searchvalue, roundto=0 - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_ValueCount(text , text , integer , double precision , double precision ) IS 'args: rastertable, rastercolumn, nband, searchvalue, roundto=0 - Returns a set of records containing a pixel band value and count of the number of pixels in a given band of a raster (or a raster coverage) that have a given set of values. If no band is specified defaults to band 1. By default nodata value pixels are not counted. and all other values in the pixel are output and pixel band values are rounded to the nearest integer.';
			
COMMENT ON FUNCTION ST_RastFromWKB(bytea ) IS 'args: wkb - Return a raster value from a Well-Known Binary (WKB) raster.';
			
COMMENT ON FUNCTION ST_RastFromHexWKB(text ) IS 'args: wkb - Return a raster value from a Hex representation of Well-Known Binary (WKB) raster.';
			
COMMENT ON FUNCTION ST_AsBinary(raster , boolean ) IS 'args: rast, outasin=FALSE - Return the Well-Known Binary (WKB) representation of the raster.';
			
COMMENT ON FUNCTION ST_AsWKB(raster , boolean ) IS 'args: rast, outasin=FALSE - Return the Well-Known Binary (WKB) representation of the raster.';
			
COMMENT ON FUNCTION ST_AsHexWKB(raster , boolean ) IS 'args: rast, outasin=FALSE - Return the Well-Known Binary (WKB) in Hex representation of the raster.';
			
COMMENT ON FUNCTION ST_AsGDALRaster(raster , text , text[] , integer ) IS 'args: rast, format, options=NULL, srid=sameassource - Return the raster tile in the designated GDAL Raster format. Raster formats are one of those supported by your compiled library. Use ST_GDALDrivers() to get a list of formats supported by your library.';
			
COMMENT ON FUNCTION ST_AsJPEG(raster , text[] ) IS 'args: rast, options=NULL - Return the raster tile selected bands as a single Joint Photographic Exports Group (JPEG) image (byte array). If no band is specified and 1 or more than 3 bands, then only the first band is used. If only 3 bands then all 3 bands are used and mapped to RGB.';
			
COMMENT ON FUNCTION ST_AsJPEG(raster , integer , integer ) IS 'args: rast, nband, quality - Return the raster tile selected bands as a single Joint Photographic Exports Group (JPEG) image (byte array). If no band is specified and 1 or more than 3 bands, then only the first band is used. If only 3 bands then all 3 bands are used and mapped to RGB.';
			
COMMENT ON FUNCTION ST_AsJPEG(raster , integer , text[] ) IS 'args: rast, nband, options=NULL - Return the raster tile selected bands as a single Joint Photographic Exports Group (JPEG) image (byte array). If no band is specified and 1 or more than 3 bands, then only the first band is used. If only 3 bands then all 3 bands are used and mapped to RGB.';
			
COMMENT ON FUNCTION ST_AsJPEG(raster , integer[] , text[] ) IS 'args: rast, nbands, options=NULL - Return the raster tile selected bands as a single Joint Photographic Exports Group (JPEG) image (byte array). If no band is specified and 1 or more than 3 bands, then only the first band is used. If only 3 bands then all 3 bands are used and mapped to RGB.';
			
COMMENT ON FUNCTION ST_AsJPEG(raster , integer[] , integer ) IS 'args: rast, nbands, quality - Return the raster tile selected bands as a single Joint Photographic Exports Group (JPEG) image (byte array). If no band is specified and 1 or more than 3 bands, then only the first band is used. If only 3 bands then all 3 bands are used and mapped to RGB.';
			
COMMENT ON FUNCTION ST_AsPNG(raster , text[] ) IS 'args: rast, options=NULL - Return the raster tile selected bands as a single portable network graphics (PNG) image (byte array). If 1, 3, or 4 bands in raster and no bands are specified, then all bands are used. If more 2 or more than 4 bands and no bands specified, then only band 1 is used. Bands are mapped to RGB or RGBA space.';
			
COMMENT ON FUNCTION ST_AsPNG(raster , integer , integer ) IS 'args: rast, nband, compression - Return the raster tile selected bands as a single portable network graphics (PNG) image (byte array). If 1, 3, or 4 bands in raster and no bands are specified, then all bands are used. If more 2 or more than 4 bands and no bands specified, then only band 1 is used. Bands are mapped to RGB or RGBA space.';
			
COMMENT ON FUNCTION ST_AsPNG(raster , integer , text[] ) IS 'args: rast, nband, options=NULL - Return the raster tile selected bands as a single portable network graphics (PNG) image (byte array). If 1, 3, or 4 bands in raster and no bands are specified, then all bands are used. If more 2 or more than 4 bands and no bands specified, then only band 1 is used. Bands are mapped to RGB or RGBA space.';
			
COMMENT ON FUNCTION ST_AsPNG(raster , integer[] , integer ) IS 'args: rast, nbands, compression - Return the raster tile selected bands as a single portable network graphics (PNG) image (byte array). If 1, 3, or 4 bands in raster and no bands are specified, then all bands are used. If more 2 or more than 4 bands and no bands specified, then only band 1 is used. Bands are mapped to RGB or RGBA space.';
			
COMMENT ON FUNCTION ST_AsPNG(raster , integer[] , text[] ) IS 'args: rast, nbands, options=NULL - Return the raster tile selected bands as a single portable network graphics (PNG) image (byte array). If 1, 3, or 4 bands in raster and no bands are specified, then all bands are used. If more 2 or more than 4 bands and no bands specified, then only band 1 is used. Bands are mapped to RGB or RGBA space.';
			
COMMENT ON FUNCTION ST_AsTIFF(raster , text[] , integer ) IS 'args: rast, options='', srid=sameassource - Return the raster selected bands as a single TIFF image (byte array). If no band is specified or any of specified bands does not exist in the raster, then will try to use all bands.';
			
COMMENT ON FUNCTION ST_AsTIFF(raster , text , integer ) IS 'args: rast, compression='', srid=sameassource - Return the raster selected bands as a single TIFF image (byte array). If no band is specified or any of specified bands does not exist in the raster, then will try to use all bands.';
			
COMMENT ON FUNCTION ST_AsTIFF(raster , integer[] , text , integer ) IS 'args: rast, nbands, compression='', srid=sameassource - Return the raster selected bands as a single TIFF image (byte array). If no band is specified or any of specified bands does not exist in the raster, then will try to use all bands.';
			
COMMENT ON FUNCTION ST_AsTIFF(raster , integer[] , text[] , integer ) IS 'args: rast, nbands, options, srid=sameassource - Return the raster selected bands as a single TIFF image (byte array). If no band is specified or any of specified bands does not exist in the raster, then will try to use all bands.';
			
COMMENT ON FUNCTION ST_Clip(raster , integer[] , geometry , double precision[] , boolean ) IS 'args: rast, nband, geom, nodataval=NULL, crop=TRUE - Returns the raster clipped by the input geometry. If band number not is specified, all bands are processed. If crop is not specified or TRUE, the output raster is cropped.';
			
COMMENT ON FUNCTION ST_Clip(raster , integer , geometry , double precision , boolean ) IS 'args: rast, nband, geom, nodataval, crop=TRUE - Returns the raster clipped by the input geometry. If band number not is specified, all bands are processed. If crop is not specified or TRUE, the output raster is cropped.';
			
COMMENT ON FUNCTION ST_Clip(raster , integer , geometry , boolean ) IS 'args: rast, nband, geom, crop - Returns the raster clipped by the input geometry. If band number not is specified, all bands are processed. If crop is not specified or TRUE, the output raster is cropped.';
			
COMMENT ON FUNCTION ST_Clip(raster , geometry , double precision[] , boolean ) IS 'args: rast, geom, nodataval=NULL, crop=TRUE - Returns the raster clipped by the input geometry. If band number not is specified, all bands are processed. If crop is not specified or TRUE, the output raster is cropped.';
			
COMMENT ON FUNCTION ST_Clip(raster , geometry , double precision , boolean ) IS 'args: rast, geom, nodataval, crop=TRUE - Returns the raster clipped by the input geometry. If band number not is specified, all bands are processed. If crop is not specified or TRUE, the output raster is cropped.';
			
COMMENT ON FUNCTION ST_Clip(raster , geometry , boolean ) IS 'args: rast, geom, crop - Returns the raster clipped by the input geometry. If band number not is specified, all bands are processed. If crop is not specified or TRUE, the output raster is cropped.';
			
COMMENT ON FUNCTION ST_ColorMap(raster , integer , text , text ) IS 'args: rast, nband=1, colormap=grayscale, method=INTERPOLATE - Creates a new raster of up to four 8BUI bands (grayscale, RGB, RGBA) from the source raster and a specified band. Band 1 is assumed if not specified.';
			
COMMENT ON FUNCTION ST_ColorMap(raster , text , text ) IS 'args: rast, colormap, method=INTERPOLATE - Creates a new raster of up to four 8BUI bands (grayscale, RGB, RGBA) from the source raster and a specified band. Band 1 is assumed if not specified.';
			
COMMENT ON FUNCTION ST_Grayscale(raster , integer , integer , integer , text ) IS 'args: rast, redband=1, greenband=2, blueband=3, extenttype=INTERSECTION - Creates a new one-8BUI band raster from the source raster and specified bands representing Red, Green and Blue';
			
COMMENT ON FUNCTION ST_Grayscale(rastbandarg[] , text ) IS 'args: rastbandargset, extenttype=INTERSECTION - Creates a new one-8BUI band raster from the source raster and specified bands representing Red, Green and Blue';
			
COMMENT ON FUNCTION ST_Intersection(geometry , raster , integer ) IS 'args: geom, rast, band_num=1 - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_Intersection(raster , geometry ) IS 'args: rast, geom - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_Intersection(raster , integer , geometry ) IS 'args: rast, band, geomin - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_Intersection(raster , raster , double precision[] ) IS 'args: rast1, rast2, nodataval - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_Intersection(raster , raster , text , double precision[] ) IS 'args: rast1, rast2, returnband, nodataval - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_Intersection(raster , integer , raster , integer , double precision[] ) IS 'args: rast1, band1, rast2, band2, nodataval - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_Intersection(raster , integer , raster , integer , text , double precision[] ) IS 'args: rast1, band1, rast2, band2, returnband, nodataval - Returns a raster or a set of geometry-pixelvalue pairs representing the shared portion of two rasters or the geometrical intersection of a vectorization of the raster and a geometry.';
			
COMMENT ON FUNCTION ST_MapAlgebra(rastbandarg[] , regprocedure , text , text , raster , integer , integer , text[] ) IS 'args: rastbandargset, callbackfunc, pixeltype=NULL, extenttype=INTERSECTION, customextent=NULL, distancex=0, distancey=0, VARIADIC userargs=NULL - Callback function version - Returns a one-band raster given one or more input rasters, band indexes and one user-specified callback function.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , integer[] , regprocedure , text , text , raster , integer , integer , text[] ) IS 'args: rast, nband, callbackfunc, pixeltype=NULL, extenttype=FIRST, customextent=NULL, distancex=0, distancey=0, VARIADIC userargs=NULL - Callback function version - Returns a one-band raster given one or more input rasters, band indexes and one user-specified callback function.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , integer , regprocedure , text , text , raster , integer , integer , text[] ) IS 'args: rast, nband, callbackfunc, pixeltype=NULL, extenttype=FIRST, customextent=NULL, distancex=0, distancey=0, VARIADIC userargs=NULL - Callback function version - Returns a one-band raster given one or more input rasters, band indexes and one user-specified callback function.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , integer , raster , integer , regprocedure , text , text , raster , integer , integer , text[] ) IS 'args: rast1, nband1, rast2, nband2, callbackfunc, pixeltype=NULL, extenttype=INTERSECTION, customextent=NULL, distancex=0, distancey=0, VARIADIC userargs=NULL - Callback function version - Returns a one-band raster given one or more input rasters, band indexes and one user-specified callback function.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster, integer, regprocedure , float8[] , boolean , text , text , raster , text[] ) IS 'args: rast, nband, callbackfunc, mask, weighted, pixeltype=NULL, extenttype=INTERSECTION, customextent=NULL, VARIADIC userargs=NULL - Callback function version - Returns a one-band raster given one or more input rasters, band indexes and one user-specified callback function.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , integer , text , text , double precision ) IS 'args: rast, nband, pixeltype, expression, nodataval=NULL - Expression version - Returns a one-band raster given one or two input rasters, band indexes and one or more user-specified SQL expressions.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , text , text , double precision ) IS 'args: rast, pixeltype, expression, nodataval=NULL - Expression version - Returns a one-band raster given one or two input rasters, band indexes and one or more user-specified SQL expressions.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , integer , raster , integer , text , text , text , text , text , double precision ) IS 'args: rast1, nband1, rast2, nband2, expression, pixeltype=NULL, extenttype=INTERSECTION, nodata1expr=NULL, nodata2expr=NULL, nodatanodataval=NULL - Expression version - Returns a one-band raster given one or two input rasters, band indexes and one or more user-specified SQL expressions.';
			
COMMENT ON FUNCTION ST_MapAlgebra(raster , raster , text , text , text , text , text , double precision ) IS 'args: rast1, rast2, expression, pixeltype=NULL, extenttype=INTERSECTION, nodata1expr=NULL, nodata2expr=NULL, nodatanodataval=NULL - Expression version - Returns a one-band raster given one or two input rasters, band indexes and one or more user-specified SQL expressions.';
			
COMMENT ON FUNCTION ST_MapAlgebraExpr(raster , integer , text , text , double precision ) IS 'args: rast, band, pixeltype, expression, nodataval=NULL - 1 raster band version: Creates a new one band raster formed by applying a valid PostgreSQL algebraic operation on the input raster band and of pixeltype provided. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraExpr(raster , text , text , double precision ) IS 'args: rast, pixeltype, expression, nodataval=NULL - 1 raster band version: Creates a new one band raster formed by applying a valid PostgreSQL algebraic operation on the input raster band and of pixeltype provided. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraExpr(raster , raster , text , text , text , text , text , double precision ) IS 'args: rast1, rast2, expression, pixeltype=same_as_rast1_band, extenttype=INTERSECTION, nodata1expr=NULL, nodata2expr=NULL, nodatanodataval=NULL - 2 raster band version: Creates a new one band raster formed by applying a valid PostgreSQL algebraic operation on the two input raster bands and of pixeltype provided. band 1 of each raster is assumed if no band numbers are specified. The resulting raster will be aligned (scale, skew and pixel corners) on the grid defined by the first raster and have its extent defined by the "extenttype" parameter. Values for "extenttype" can be: INTERSECTION, UNION, FIRST, SECOND.';
			
COMMENT ON FUNCTION ST_MapAlgebraExpr(raster , integer , raster , integer , text , text , text , text , text , double precision ) IS 'args: rast1, band1, rast2, band2, expression, pixeltype=same_as_rast1_band, extenttype=INTERSECTION, nodata1expr=NULL, nodata2expr=NULL, nodatanodataval=NULL - 2 raster band version: Creates a new one band raster formed by applying a valid PostgreSQL algebraic operation on the two input raster bands and of pixeltype provided. band 1 of each raster is assumed if no band numbers are specified. The resulting raster will be aligned (scale, skew and pixel corners) on the grid defined by the first raster and have its extent defined by the "extenttype" parameter. Values for "extenttype" can be: INTERSECTION, UNION, FIRST, SECOND.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, regprocedure) IS 'args: rast, onerasteruserfunc - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, regprocedure, text[]) IS 'args: rast, onerasteruserfunc, VARIADIC args - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, text, regprocedure) IS 'args: rast, pixeltype, onerasteruserfunc - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, text, regprocedure, text[]) IS 'args: rast, pixeltype, onerasteruserfunc, VARIADIC args - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, integer, regprocedure) IS 'args: rast, band, onerasteruserfunc - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, integer, regprocedure, text[]) IS 'args: rast, band, onerasteruserfunc, VARIADIC args - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, integer, text, regprocedure) IS 'args: rast, band, pixeltype, onerasteruserfunc - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, integer, text, regprocedure, text[]) IS 'args: rast, band, pixeltype, onerasteruserfunc, VARIADIC args - 1 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the input raster band and of pixeltype prodived. Band 1 is assumed if no band is specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, raster, regprocedure, text, text, text[]) IS 'args: rast1, rast2, tworastuserfunc, pixeltype=same_as_rast1, extenttype=INTERSECTION, VARIADIC userargs - 2 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the 2 input raster bands and of pixeltype prodived. Band 1 is assumed if no band is specified. Extent type defaults to INTERSECTION if not specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFct(raster, integer, raster, integer, regprocedure, text, text, text[]) IS 'args: rast1, band1, rast2, band2, tworastuserfunc, pixeltype=same_as_rast1, extenttype=INTERSECTION, VARIADIC userargs - 2 band version - Creates a new one band raster formed by applying a valid PostgreSQL function on the 2 input raster bands and of pixeltype prodived. Band 1 is assumed if no band is specified. Extent type defaults to INTERSECTION if not specified.';
			
COMMENT ON FUNCTION ST_MapAlgebraFctNgb(raster , integer , text , integer , integer , regprocedure , text , text[] ) IS 'args: rast, band, pixeltype, ngbwidth, ngbheight, onerastngbuserfunc, nodatamode, VARIADIC args - 1-band version: Map Algebra Nearest Neighbor using user-defined PostgreSQL function. Return a raster which values are the result of a PLPGSQL user function involving a neighborhood of values from the input raster band.';
			
COMMENT ON FUNCTION ST_Reclass(raster , integer , text , text , double precision ) IS 'args: rast, nband, reclassexpr, pixeltype, nodataval=NULL - Creates a new raster composed of band types reclassified from original. The nband is the band to be changed. If nband is not specified assumed to be 1. All other bands are returned unchanged. Use case: convert a 16BUI band to a 8BUI and so forth for simpler rendering as viewable formats.';
			
COMMENT ON FUNCTION ST_Reclass(raster , reclassarg[] ) IS 'args: rast, VARIADIC reclassargset - Creates a new raster composed of band types reclassified from original. The nband is the band to be changed. If nband is not specified assumed to be 1. All other bands are returned unchanged. Use case: convert a 16BUI band to a 8BUI and so forth for simpler rendering as viewable formats.';
			
COMMENT ON FUNCTION ST_Reclass(raster , text , text ) IS 'args: rast, reclassexpr, pixeltype - Creates a new raster composed of band types reclassified from original. The nband is the band to be changed. If nband is not specified assumed to be 1. All other bands are returned unchanged. Use case: convert a 16BUI band to a 8BUI and so forth for simpler rendering as viewable formats.';
			
COMMENT ON FUNCTION ST_Union(setof raster ) IS 'args: rast - Returns the union of a set of raster tiles into a single raster composed of 1 or more bands.';
			
COMMENT ON FUNCTION ST_Union(setof raster , unionarg[] ) IS 'args: rast, unionargset - Returns the union of a set of raster tiles into a single raster composed of 1 or more bands.';
			
COMMENT ON FUNCTION ST_Union(setof raster, integer) IS 'args: rast, nband - Returns the union of a set of raster tiles into a single raster composed of 1 or more bands.';
			
COMMENT ON FUNCTION ST_Union(setof raster, text) IS 'args: rast, uniontype - Returns the union of a set of raster tiles into a single raster composed of 1 or more bands.';
			
COMMENT ON FUNCTION ST_Union(setof raster, integer, text) IS 'args: rast, nband, uniontype - Returns the union of a set of raster tiles into a single raster composed of 1 or more bands.';
			
COMMENT ON FUNCTION ST_Distinct4ma(float8[][], text, text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the number of unique pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_Distinct4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the number of unique pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_InvDistWeight4ma(double precision[][][], integer[][], text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that interpolates a pixels value from the pixels neighborhood.';
			
COMMENT ON FUNCTION ST_Max4ma(float8[][], text, text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the maximum pixel value in a neighborhood.';
			
COMMENT ON FUNCTION ST_Max4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the maximum pixel value in a neighborhood.';
			
COMMENT ON FUNCTION ST_Mean4ma(float8[][], text, text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the mean pixel value in a neighborhood.';
			
COMMENT ON FUNCTION ST_Mean4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the mean pixel value in a neighborhood.';
			
COMMENT ON FUNCTION ST_Min4ma(float8[][], text , text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the minimum pixel value in a neighborhood.';
			
COMMENT ON FUNCTION ST_Min4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the minimum pixel value in a neighborhood.';
			
COMMENT ON FUNCTION ST_MinDist4ma(double precision[][][], integer[][], text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that returns the minimum distance (in number of pixels) between the pixel of interest and a neighboring pixel with value.';
			
COMMENT ON FUNCTION ST_Range4ma(float8[][], text, text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the range of pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_Range4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the range of pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_StdDev4ma(float8[][], text , text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the standard deviation of pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_StdDev4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the standard deviation of pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_Sum4ma(float8[][], text, text[]) IS 'args: matrix, nodatamode, VARIADIC args - Raster processing function that calculates the sum of all pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_Sum4ma(double precision[][][], integer[][] , text[]) IS 'args: value, pos, VARIADIC userargs - Raster processing function that calculates the sum of all pixel values in a neighborhood.';
			
COMMENT ON FUNCTION ST_Aspect(raster , integer , text , text , boolean ) IS 'args: rast, band=1, pixeltype=32BF, units=DEGREES, interpolate_nodata=FALSE - Returns the aspect (in degrees by default) of an elevation raster band. Useful for analyzing terrain.';
			
COMMENT ON FUNCTION ST_Aspect(raster , integer , raster , text , text , boolean ) IS 'args: rast, band, customextent, pixeltype=32BF, units=DEGREES, interpolate_nodata=FALSE - Returns the aspect (in degrees by default) of an elevation raster band. Useful for analyzing terrain.';
			
COMMENT ON FUNCTION ST_HillShade(raster , integer , text , double precision , double precision , double precision , double precision , boolean ) IS 'args: rast, band=1, pixeltype=32BF, azimuth=315, altitude=45, max_bright=255, scale=1.0, interpolate_nodata=FALSE - Returns the hypothetical illumination of an elevation raster band using provided azimuth, altitude, brightness and scale inputs.';
			
COMMENT ON FUNCTION ST_HillShade(raster , integer , raster , text , double precision , double precision , double precision , double precision , boolean ) IS 'args: rast, band, customextent, pixeltype=32BF, azimuth=315, altitude=45, max_bright=255, scale=1.0, interpolate_nodata=FALSE - Returns the hypothetical illumination of an elevation raster band using provided azimuth, altitude, brightness and scale inputs.';
			
COMMENT ON FUNCTION ST_Roughness(raster , integer , raster , text , boolean ) IS 'args: rast, nband, customextent, pixeltype="32BF", interpolate_nodata=FALSE - Returns a raster with the calculated "roughness" of a DEM.';
			
COMMENT ON FUNCTION ST_Slope(raster , integer , text , text , double precision , boolean ) IS 'args: rast, nband=1, pixeltype=32BF, units=DEGREES, scale=1.0, interpolate_nodata=FALSE - Returns the slope (in degrees by default) of an elevation raster band. Useful for analyzing terrain.';
			
COMMENT ON FUNCTION ST_Slope(raster , integer , raster , text , text , double precision , boolean ) IS 'args: rast, nband, customextent, pixeltype=32BF, units=DEGREES, scale=1.0, interpolate_nodata=FALSE - Returns the slope (in degrees by default) of an elevation raster band. Useful for analyzing terrain.';
			
COMMENT ON FUNCTION ST_TPI(raster , integer , raster , text , boolean ) IS 'args: rast, nband, customextent, pixeltype="32BF", interpolate_nodata=FALSE - Returns a raster with the calculated Topographic Position Index.';
			
COMMENT ON FUNCTION ST_TRI(raster , integer , raster , text , boolean ) IS 'args: rast, nband, customextent, pixeltype="32BF", interpolate_nodata=FALSE - Returns a raster with the calculated Terrain Ruggedness Index.';
			
COMMENT ON FUNCTION Box3D(raster ) IS 'args: rast - Returns the box 3d representation of the enclosing box of the raster.';
			
COMMENT ON FUNCTION ST_ConvexHull(raster ) IS 'args: rast - Return the convex hull geometry of the raster including pixel values equal to BandNoDataValue. For regular shaped and non-skewed rasters, this gives the same result as ST_Envelope so only useful for irregularly shaped or skewed rasters.';
			
COMMENT ON FUNCTION ST_DumpAsPolygons(raster , integer , boolean ) IS 'args: rast, band_num=1, exclude_nodata_value=TRUE - Returns a set of geomval (geom,val) rows, from a given raster band. If no band number is specified, band num defaults to 1.';
			
COMMENT ON FUNCTION ST_Envelope(raster ) IS 'args: rast - Returns the polygon representation of the extent of the raster.';
			
COMMENT ON FUNCTION ST_MinConvexHull(raster , integer ) IS 'args: rast, nband=NULL - Return the convex hull geometry of the raster excluding NODATA pixels.';
			
COMMENT ON FUNCTION ST_Polygon(raster , integer ) IS 'args: rast, band_num=1 - Returns a multipolygon geometry formed by the union of pixels that have a pixel value that is not no data value. If no band number is specified, band num defaults to 1.';
			
COMMENT ON FUNCTION ST_Contains(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if no points of raster rastB lie in the exterior of raster rastA and at least one point of the interior of rastB lies in the interior of rastA.';
			
COMMENT ON FUNCTION ST_Contains(raster , raster ) IS 'args: rastA, rastB - Return true if no points of raster rastB lie in the exterior of raster rastA and at least one point of the interior of rastB lies in the interior of rastA.';
			
COMMENT ON FUNCTION ST_ContainsProperly(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if rastB intersects the interior of rastA but not the boundary or exterior of rastA.';
			
COMMENT ON FUNCTION ST_ContainsProperly(raster , raster ) IS 'args: rastA, rastB - Return true if rastB intersects the interior of rastA but not the boundary or exterior of rastA.';
			
COMMENT ON FUNCTION ST_Covers(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if no points of raster rastB lie outside raster rastA.';
			
COMMENT ON FUNCTION ST_Covers(raster , raster ) IS 'args: rastA, rastB - Return true if no points of raster rastB lie outside raster rastA.';
			
COMMENT ON FUNCTION ST_CoveredBy(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if no points of raster rastA lie outside raster rastB.';
			
COMMENT ON FUNCTION ST_CoveredBy(raster , raster ) IS 'args: rastA, rastB - Return true if no points of raster rastA lie outside raster rastB.';
			
COMMENT ON FUNCTION ST_Disjoint(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if raster rastA does not spatially intersect rastB.';
			
COMMENT ON FUNCTION ST_Disjoint(raster , raster ) IS 'args: rastA, rastB - Return true if raster rastA does not spatially intersect rastB.';
			
COMMENT ON FUNCTION ST_Intersects(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if raster rastA spatially intersects raster rastB.';
			
COMMENT ON FUNCTION ST_Intersects(raster , raster ) IS 'args: rastA, rastB - Return true if raster rastA spatially intersects raster rastB.';
			
COMMENT ON FUNCTION ST_Intersects(raster , integer , geometry ) IS 'args: rast, nband, geommin - Return true if raster rastA spatially intersects raster rastB.';
			
COMMENT ON FUNCTION ST_Intersects(raster , geometry , integer ) IS 'args: rast, geommin, nband=NULL - Return true if raster rastA spatially intersects raster rastB.';
			
COMMENT ON FUNCTION ST_Intersects(geometry , raster , integer ) IS 'args: geommin, rast, nband=NULL - Return true if raster rastA spatially intersects raster rastB.';
			
COMMENT ON FUNCTION ST_Overlaps(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if raster rastA and rastB intersect but one does not completely contain the other.';
			
COMMENT ON FUNCTION ST_Overlaps(raster , raster ) IS 'args: rastA, rastB - Return true if raster rastA and rastB intersect but one does not completely contain the other.';
			
COMMENT ON FUNCTION ST_Touches(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if raster rastA and rastB have at least one point in common but their interiors do not intersect.';
			
COMMENT ON FUNCTION ST_Touches(raster , raster ) IS 'args: rastA, rastB - Return true if raster rastA and rastB have at least one point in common but their interiors do not intersect.';
			
COMMENT ON FUNCTION ST_SameAlignment(raster , raster ) IS 'args: rastA, rastB - Returns true if rasters have same skew, scale, spatial ref, and offset (pixels can be put on same grid without cutting into pixels) and false if they dont with notice detailing issue.';
			
COMMENT ON FUNCTION ST_SameAlignment(double precision , double precision , double precision , double precision , double precision , double precision , double precision , double precision , double precision , double precision , double precision , double precision ) IS 'args: ulx1, uly1, scalex1, scaley1, skewx1, skewy1, ulx2, uly2, scalex2, scaley2, skewx2, skewy2 - Returns true if rasters have same skew, scale, spatial ref, and offset (pixels can be put on same grid without cutting into pixels) and false if they dont with notice detailing issue.';
			
COMMENT ON AGGREGATE ST_SameAlignment(raster) IS 'args: rastfield - Returns true if rasters have same skew, scale, spatial ref, and offset (pixels can be put on same grid without cutting into pixels) and false if they dont with notice detailing issue.';
			
COMMENT ON FUNCTION ST_NotSameAlignmentReason(raster , raster ) IS 'args: rastA, rastB - Returns text stating if rasters are aligned and if not aligned, a reason why.';
			
COMMENT ON FUNCTION ST_Within(raster , integer , raster , integer ) IS 'args: rastA, nbandA, rastB, nbandB - Return true if no points of raster rastA lie in the exterior of raster rastB and at least one point of the interior of rastA lies in the interior of rastB.';
			
COMMENT ON FUNCTION ST_Within(raster , raster ) IS 'args: rastA, rastB - Return true if no points of raster rastA lie in the exterior of raster rastB and at least one point of the interior of rastA lies in the interior of rastB.';
			
COMMENT ON FUNCTION ST_DWithin(raster , integer , raster , integer , double precision ) IS 'args: rastA, nbandA, rastB, nbandB, distance_of_srid - Return true if rasters rastA and rastB are within the specified distance of each other.';
			
COMMENT ON FUNCTION ST_DWithin(raster , raster , double precision ) IS 'args: rastA, rastB, distance_of_srid - Return true if rasters rastA and rastB are within the specified distance of each other.';
			
COMMENT ON FUNCTION ST_DFullyWithin(raster , integer , raster , integer , double precision ) IS 'args: rastA, nbandA, rastB, nbandB, distance_of_srid - Return true if rasters rastA and rastB are fully within the specified distance of each other.';
			
COMMENT ON FUNCTION ST_DFullyWithin(raster , raster , double precision ) IS 'args: rastA, rastB, distance_of_srid - Return true if rasters rastA and rastB are fully within the specified distance of each other.';
			
    COMMENT ON TYPE geomval IS 'postgis raster type: A spatial datatype with two fields - geom (holding a geometry object) and val (holding a double precision pixel value from a raster band).';
            
        
    COMMENT ON TYPE addbandarg IS 'postgis raster type: A composite type used as input into the ST_AddBand function defining the attributes and initial value of the new band.';
            
        
    COMMENT ON TYPE rastbandarg IS 'postgis raster type: A composite type for use when needing to express a raster and a band index of that raster.';
            
        
    COMMENT ON TYPE raster IS 'postgis raster type: raster spatial data type.';
            
        
    COMMENT ON TYPE reclassarg IS 'postgis raster type: A composite type used as input into the ST_Reclass function defining the behavior of reclassification.';
            
        
    COMMENT ON TYPE summarystats IS 'postgis raster type: A composite type returned by the ST_SummaryStats and ST_SummaryStatsAgg functions.';
            
        
    COMMENT ON TYPE unionarg IS 'postgis raster type: A composite type used as input into the ST_Union function defining the bands to be processed and behavior of the UNION operation.';
            
        -- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
--
----
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2011 Regina Obe <lr@pcorp.us>
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- Author: Regina Obe <lr@pcorp.us>
--
-- This drops extension helper functions
-- and should be called at the end of the extension upgrade file
DROP FUNCTION postgis_extension_remove_objects(text, text);
DROP FUNCTION postgis_extension_drop_if_exists(text, text);
DROP FUNCTION postgis_extension_AddToSearchPath(varchar);
