BEGIN;











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

COMMIT;
