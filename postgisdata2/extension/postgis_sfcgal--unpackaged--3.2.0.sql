\echo Use "CREATE EXTENSION postgis_sfcgal" to load this file. \quit
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












-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2020 Regina Obe <lr@pcorp.us>
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
-- These are functions that need to be dropped beforehand
-- where the argument names may have changed  --
-- so have to be dropped before upgrade can happen --
-- argument names changed --

--
-- UPGRADE SCRIPT TO PostGIS 3.2
--

LOAD '$libdir/postgis_sfcgal-3';

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
    -- postgis_scripts_installed() as in 1.0 because
    -- in the 1.0 => 1.1 transition that would result
    -- in an impossible upgrade:
    --
    --   from 0.3.0 to 1.1.0
    --
    -- Next releases will still be ok as
    -- postgis_lib_version() and postgis_scripts_installed()
    -- would both return actual PostGIS release number.
    --
    BEGIN
        SELECT into old_scripts postgis_lib_version();
    EXCEPTION WHEN OTHERS THEN
        RAISE DEBUG 'Got %', SQLERRM;
        SELECT into old_scripts postgis_scripts_installed();
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
        RAISE EXCEPTION 'Upgrade of postgis from version % to version % requires a dump/reload. See PostGIS manual for instructions', old_scripts, new_scripts;
    END IF;

    WITH versions AS (
      SELECT '3.2'::text as upgraded,
      postgis_scripts_installed() as installed
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

CREATE OR REPLACE FUNCTION postgis_sfcgal_scripts_installed() RETURNS text
	AS $$ SELECT trim('3.2.0'::text || $rev$ c3e3cc0 $rev$) AS version $$
	LANGUAGE 'sql' IMMUTABLE;
CREATE OR REPLACE FUNCTION postgis_sfcgal_version() RETURNS text
        AS '$libdir/postgis_sfcgal-3'
        LANGUAGE 'c' IMMUTABLE;
CREATE OR REPLACE FUNCTION postgis_sfcgal_noop(geometry)
        RETURNS geometry
        AS '$libdir/postgis_sfcgal-3', 'postgis_sfcgal_noop'
        LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
        COST 1;
CREATE OR REPLACE FUNCTION ST_3DIntersection(geom1 geometry, geom2 geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_intersection3D'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_3DDifference(geom1 geometry, geom2 geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_difference3D'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_3DUnion(geom1 geometry, geom2 geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_union3D'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_Tesselate(geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_tesselate'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_3DArea(geometry)
       RETURNS FLOAT8
       AS '$libdir/postgis_sfcgal-3','sfcgal_area3D'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_Extrude(geometry, float8, float8, float8)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_extrude'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_ForceLHR(geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_force_lhr'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_Orientation(geometry)
       RETURNS INT4
       AS '$libdir/postgis_sfcgal-3','sfcgal_orientation'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_MinkowskiSum(geometry, geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_minkowski_sum'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_StraightSkeleton(geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_straight_skeleton'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_ApproximateMedialAxis(geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_approximate_medial_axis'
       LANGUAGE 'c'
       IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_IsPlanar(geometry)
       RETURNS boolean
       AS '$libdir/postgis_sfcgal-3','sfcgal_is_planar'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_Volume(geometry)
       RETURNS FLOAT8
       AS '$libdir/postgis_sfcgal-3','sfcgal_volume'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_MakeSolid(geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3','sfcgal_make_solid'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_IsSolid(geometry)
       RETURNS boolean
       AS '$libdir/postgis_sfcgal-3','sfcgal_is_solid'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
CREATE OR REPLACE FUNCTION ST_ConstrainedDelaunayTriangles(geometry)
       RETURNS geometry
       AS '$libdir/postgis_sfcgal-3', 'ST_ConstrainedDelaunayTriangles'
       LANGUAGE 'c' IMMUTABLE STRICT PARALLEL SAFE
       COST 100;
DROP FUNCTION _postgis_upgrade_info();











-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- Copyright (C) 2020 Regina Obe <lr@pcorp.us>
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
--
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
-- These are reserved for functions that are changed to use default args
-- This is installed after the new functions are installed
-- We don't have any of these yet for sfcgal
-- The reason we put these after install is
-- you can't drop a function that is used by sql functions
-- without forcing a drop on those as well which may cause issues with user functions.
-- This allows us to CREATE OR REPLACE those in general sfcgal.sql.in
-- without dropping them.



COMMENT ON FUNCTION postgis_sfcgal_version() IS 'Returns the version of SFCGAL in use';
			
COMMENT ON FUNCTION ST_Extrude(geometry, float, float, float) IS 'args: geom, x, y, z - Extrude a surface to a related volume';
			
COMMENT ON FUNCTION ST_StraightSkeleton(geometry) IS 'args: geom - Compute a straight skeleton from a geometry';
			
COMMENT ON FUNCTION ST_ApproximateMedialAxis(geometry) IS 'args: geom - Compute the approximate medial axis of an areal geometry.';
			
COMMENT ON FUNCTION ST_IsPlanar(geometry) IS 'args: geom - Check if a surface is or not planar';
			
COMMENT ON FUNCTION ST_Orientation(geometry) IS 'args: geom - Determine surface orientation';
			
COMMENT ON FUNCTION ST_ForceLHR(geometry) IS 'args: geom - Force LHR orientation';
			
COMMENT ON FUNCTION ST_MinkowskiSum(geometry, geometry) IS 'args: geom1, geom2 - Performs Minkowski sum';
			
COMMENT ON FUNCTION ST_ConstrainedDelaunayTriangles(geometry ) IS 'args: g1 - Return a constrained Delaunay triangulation around the given input geometry.';
			
COMMENT ON FUNCTION ST_3DIntersection(geometry, geometry) IS 'args: geom1, geom2 - Perform 3D intersection';
			
COMMENT ON FUNCTION ST_3DDifference(geometry, geometry) IS 'args: geom1, geom2 - Perform 3D difference';
			
COMMENT ON FUNCTION ST_3DUnion(geometry, geometry) IS 'args: geom1, geom2 - Perform 3D union';
			
COMMENT ON FUNCTION ST_3DArea(geometry) IS 'args: geom1 - Computes area of 3D surface geometries. Will return 0 for solids.';
			
COMMENT ON FUNCTION ST_Tesselate(geometry) IS 'args: geom - Perform surface Tesselation of a polygon or polyhedralsurface and returns as a TIN or collection of TINS';
			
COMMENT ON FUNCTION ST_Volume(geometry) IS 'args: geom1 - Computes the volume of a 3D solid. If applied to surface (even closed) geometries will return 0.';
			
COMMENT ON FUNCTION ST_MakeSolid(geometry) IS 'args: geom1 - Cast the geometry into a solid. No check is performed. To obtain a valid solid, the input geometry must be a closed Polyhedral Surface or a closed TIN.';
			
COMMENT ON FUNCTION ST_IsSolid(geometry) IS 'args: geom1 - Test if the geometry is a solid. No validity check is performed.';
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
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
--
-- PostGIS - Spatial Types for PostgreSQL
-- http://postgis.net
--
-- This is free software; you can redistribute and/or modify it under
-- the terms of the GNU General Public Licence. See the COPYING file.
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
--
-- Generated on: 2021-12-30 08:19:19
--           by: ../../utils/create_unpackaged.pl
--          for: postgis_sfcgal
--         from: -
--
-- Do not edit manually, your changes will be lost.
--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- complain if script is sourced in psql
\echo Use "CREATE EXTENSION postgis_sfcgal" to load this file. \quit

-- Register all views.
-- Register all tables.
-- Register all sequences.
-- Register all aggregates.
-- Register all operators classes and families.
-- Register all operators.
-- Register all casts.
-- Register all functions except 0 needed for type definition.
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION postgis_sfcgal_scripts_installed ();
 RAISE NOTICE 'newly registered FUNCTION postgis_sfcgal_scripts_installed ()';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION postgis_sfcgal_scripts_installed ()';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION postgis_sfcgal_version ();
 RAISE NOTICE 'newly registered FUNCTION postgis_sfcgal_version ()';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION postgis_sfcgal_version ()';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION postgis_sfcgal_noop (geometry);
 RAISE NOTICE 'newly registered FUNCTION postgis_sfcgal_noop (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION postgis_sfcgal_noop (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_3DIntersection (geom1 geometry, geom2 geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_3DIntersection (geom1 geometry, geom2 geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_3DIntersection (geom1 geometry, geom2 geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_3DDifference (geom1 geometry, geom2 geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_3DDifference (geom1 geometry, geom2 geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_3DDifference (geom1 geometry, geom2 geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_3DUnion (geom1 geometry, geom2 geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_3DUnion (geom1 geometry, geom2 geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_3DUnion (geom1 geometry, geom2 geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_Tesselate (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_Tesselate (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_Tesselate (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_3DArea (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_3DArea (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_3DArea (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_Extrude (geometry, float8, float8, float8);
 RAISE NOTICE 'newly registered FUNCTION ST_Extrude (geometry, float8, float8, float8)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_Extrude (geometry, float8, float8, float8)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_ForceLHR (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_ForceLHR (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_ForceLHR (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_Orientation (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_Orientation (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_Orientation (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_MinkowskiSum (geometry, geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_MinkowskiSum (geometry, geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_MinkowskiSum (geometry, geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_StraightSkeleton (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_StraightSkeleton (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_StraightSkeleton (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_ApproximateMedialAxis (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_ApproximateMedialAxis (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_ApproximateMedialAxis (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_IsPlanar (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_IsPlanar (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_IsPlanar (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_Volume (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_Volume (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_Volume (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_MakeSolid (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_MakeSolid (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_MakeSolid (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_IsSolid (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_IsSolid (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_IsSolid (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
DO $$
BEGIN
 ALTER EXTENSION postgis_sfcgal ADD FUNCTION ST_ConstrainedDelaunayTriangles (geometry);
 RAISE NOTICE 'newly registered FUNCTION ST_ConstrainedDelaunayTriangles (geometry)';
EXCEPTION WHEN object_not_in_prerequisite_state THEN
  IF SQLERRM ~ '\mpostgis_sfcgal\M'
  THEN
    RAISE NOTICE 'already registered FUNCTION ST_ConstrainedDelaunayTriangles (geometry)';
  ELSE
    RAISE EXCEPTION '%', SQLERRM;
  END IF;
END;
$$ LANGUAGE 'plpgsql';
-- Add all functions needed for types definition (needed?).
-- Register all types.

