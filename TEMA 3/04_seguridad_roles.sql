/* =====================================================================
   SCRIPT   : 04_seguridad_roles.sql
   OBJETIVO : roles con privilegios diferenciados (administrador / analista / auditor),
              auditoría a nivel de servidor y cifrado en reposo (TDE).
   ALINEACIÓN: Ley N.° 29733 (arts. 7 proporcionalidad, 9 seguridad, 16 seguridad del
              tratamiento) y su Reglamento (D.S. 003-2013-JUS, medidas de seguridad);
              ISO/IEC 27001:2022 Anexo A: 5.15 control de acceso, 5.3 segregación de
              funciones, 8.2 acceso privilegiado, 8.3 restricción de acceso a información,
              8.15 registro, 8.24 criptografía.
   PRINCIPIOS: mínimo privilegio · segregación de funciones (quien administra datos NO lee
              ni modifica el log; quien audita NO modifica datos) · el analista solo ve
              datos agregados/generalizados (sin localidad ni edad exacta).
   NOTA      : no ejecutado contra una instancia real al redactarlo. Reemplace todo lo que
              esté entre << >>. No guarde contraseñas reales en el repositorio.
   ===================================================================== */

/* ---------- 1. Inicios de sesión de PRUEBA (nivel servidor) ---------- */
USE master;
GO
DECLARE @sql NVARCHAR(MAX) = N'';
IF SUSER_ID(N'login_admin_demo') IS NULL
    SET @sql += N'CREATE LOGIN login_admin_demo    WITH PASSWORD = N''<<CONTRASEÑA_ROBUSTA_1>>'', CHECK_POLICY = ON, CHECK_EXPIRATION = ON;';
IF SUSER_ID(N'login_analista_demo') IS NULL
    SET @sql += N'CREATE LOGIN login_analista_demo WITH PASSWORD = N''<<CONTRASEÑA_ROBUSTA_2>>'', CHECK_POLICY = ON, CHECK_EXPIRATION = ON;';
IF SUSER_ID(N'login_auditor_demo') IS NULL
    SET @sql += N'CREATE LOGIN login_auditor_demo  WITH PASSWORD = N''<<CONTRASEÑA_ROBUSTA_3>>'', CHECK_POLICY = ON, CHECK_EXPIRATION = ON;';
EXEC sys.sp_executesql @sql;
-- BULK INSERT dentro de SQL dinámico exige este permiso de servidor a quien carga datos
GRANT ADMINISTER BULK OPERATIONS TO login_admin_demo;
GO

/* ---------- 2. Usuarios, roles y vista analítica (base de datos) ---------- */
USE DIRESA_LL_Vigilancia;
GO
IF DATABASE_PRINCIPAL_ID(N'usr_admin_demo')    IS NULL CREATE USER usr_admin_demo    FOR LOGIN login_admin_demo;
IF DATABASE_PRINCIPAL_ID(N'usr_analista_demo') IS NULL CREATE USER usr_analista_demo FOR LOGIN login_analista_demo;
IF DATABASE_PRINCIPAL_ID(N'usr_auditor_demo')  IS NULL CREATE USER usr_auditor_demo  FOR LOGIN login_auditor_demo;

IF DATABASE_PRINCIPAL_ID(N'rol_admin_vigilancia') IS NULL CREATE ROLE rol_admin_vigilancia;
IF DATABASE_PRINCIPAL_ID(N'rol_analista_datos')   IS NULL CREATE ROLE rol_analista_datos;
IF DATABASE_PRINCIPAL_ID(N'rol_auditor')          IS NULL CREATE ROLE rol_auditor;
GO

/* Vista para el analista: minimiza datos (Ley 29733, art. 7). Sin localidad, localcod, caso_id
   ni edad exacta (se generaliza en grupo etario). */
CREATE OR ALTER VIEW vig.vw_caso_analitico
AS
SELECT u.departamento, u.provincia, u.distrito,
       e.grupo, e.diagnostic, e.enfermedad,
       c.ano, c.semana, c.tipo_dx, c.sexo,
       grupo_etario = CASE WHEN c.edad_anios IS NULL THEN 'SIN DATO'
                           WHEN c.edad_anios <  1  THEN '<1'
                           WHEN c.edad_anios <  5  THEN '1-4'
                           WHEN c.edad_anios < 15  THEN '5-14'
                           WHEN c.edad_anios < 30  THEN '15-29'
                           WHEN c.edad_anios < 60  THEN '30-59'
                           ELSE '60+' END,
       c.dup_seq
FROM vig.caso c
JOIN vig.ubigeo    u ON u.ubigeo     = c.ubigeo
JOIN vig.enfermedad e ON e.diagnostic = c.diagnostic;
GO

/* ---------- 3. ROL ADMINISTRADOR (administra y carga datos; NO toca el log) ---------- */
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, ALTER ON SCHEMA::vig TO rol_admin_vigilancia;
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER           ON SCHEMA::stg TO rol_admin_vigilancia; -- ALTER: TRUNCATE de staging
GRANT SELECT ON aud.lote_ingesta TO rol_admin_vigilancia;
GRANT SELECT ON aud.cuarentena   TO rol_admin_vigilancia;
DENY  SELECT, INSERT, UPDATE, DELETE ON aud.log_auditoria TO rol_admin_vigilancia;   -- segregación de funciones
DENY  SELECT, INSERT, UPDATE, DELETE ON aud.prueba_restauracion TO rol_admin_vigilancia;
-- Los procedimientos y triggers escriben en aud.* por CADENA DE PROPIEDAD (mismo propietario dbo);
-- por eso el administrador puede cargar datos aunque tenga DENY directo sobre el log.
GO

/* ---------- 4. ROL ANALISTA (solo lectura de datos generalizados) ---------- */
GRANT SELECT ON vig.vw_caso_analitico      TO rol_analista_datos;
GRANT SELECT ON vig.fn_casos_por_periodo   TO rol_analista_datos;   -- función con valor de tabla
GRANT SELECT ON vig.ubigeo                 TO rol_analista_datos;
GRANT SELECT ON vig.enfermedad             TO rol_analista_datos;
DENY  SELECT ON vig.caso                   TO rol_analista_datos;   -- sin acceso a la tabla base (la vista accede por cadena)
DENY  INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::vig TO rol_analista_datos;
DENY  SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::stg TO rol_analista_datos;
DENY  SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::aud TO rol_analista_datos;
GO
-- Nota: DENY EXECUTE/ALTER sobre vig no impide el SELECT concedido a objetos concretos.

/* ---------- 5. ROL AUDITOR (solo lectura del log y metadatos; nunca modifica) ---------- */
GRANT SELECT ON SCHEMA::aud TO rol_auditor;
GRANT VIEW DEFINITION ON SCHEMA::vig TO rol_auditor;               -- ver definiciones, no datos
DENY  INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::aud TO rol_auditor;
DENY  SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::vig TO rol_auditor;
DENY  SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::stg TO rol_auditor;
GO

/* ---------- 6. Membresías ---------- */
ALTER ROLE rol_admin_vigilancia ADD MEMBER usr_admin_demo;
ALTER ROLE rol_analista_datos   ADD MEMBER usr_analista_demo;
ALTER ROLE rol_auditor          ADD MEMBER usr_auditor_demo;
GO

/* ---------- 7. PRUEBAS de privilegios (cada bloque indica el resultado esperado) ---------- */
EXECUTE AS USER = 'usr_analista_demo';
    SELECT TOP (5) * FROM vig.vw_caso_analitico;                        -- OK
    SELECT TOP (5) * FROM vig.fn_casos_por_periodo(2024,1,53,'13',0);   -- OK
    BEGIN TRY SELECT TOP (1) * FROM vig.caso; END TRY                   -- ERROR 229 (permiso denegado)
    BEGIN CATCH SELECT 'analista -> vig.caso' AS intento, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje; END CATCH;
    BEGIN TRY SELECT TOP (1) * FROM aud.log_auditoria; END TRY          -- ERROR 229
    BEGIN CATCH SELECT 'analista -> aud.log' AS intento, ERROR_NUMBER() AS error; END CATCH;
REVERT;
EXECUTE AS USER = 'usr_auditor_demo';
    SELECT TOP (5) * FROM aud.log_auditoria ORDER BY log_id DESC;       -- OK
    BEGIN TRY DELETE aud.log_auditoria; END TRY                          -- ERROR 229
    BEGIN CATCH SELECT 'auditor -> DELETE log' AS intento, ERROR_NUMBER() AS error; END CATCH;
    BEGIN TRY SELECT TOP (1) * FROM vig.caso; END TRY                    -- ERROR 229
    BEGIN CATCH SELECT 'auditor -> vig.caso' AS intento, ERROR_NUMBER() AS error; END CATCH;
REVERT;
EXECUTE AS USER = 'usr_admin_demo';
    SELECT COUNT(*) AS casos FROM vig.caso;                              -- OK
    BEGIN TRY SELECT TOP (1) * FROM aud.log_auditoria; END TRY           -- ERROR 229
    BEGIN CATCH SELECT 'admin -> aud.log' AS intento, ERROR_NUMBER() AS error; END CATCH;
REVERT;
GO
-- Matriz efectiva (evidencia para el auditor):
SELECT dp.name AS rol, perm.permission_name, perm.state_desc, ISNULL(OBJECT_SCHEMA_NAME(perm.major_id) + '.' + OBJECT_NAME(perm.major_id),
       CASE perm.class WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(perm.major_id) END) AS objeto
FROM sys.database_permissions perm
JOIN sys.database_principals dp ON dp.principal_id = perm.grantee_principal_id
WHERE dp.name IN ('rol_admin_vigilancia','rol_analista_datos','rol_auditor')
ORDER BY dp.name, objeto, perm.permission_name;
GO

/* ---------- 8. AUDITORÍA DE SERVIDOR (ISO 27001 A.8.15) ---------- */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'audit_vigilancia')
BEGIN
    CREATE SERVER AUDIT audit_vigilancia
        TO FILE (FILEPATH = N'<<D:\SQLAudit\>>', MAXSIZE = 100 MB, MAX_ROLLOVER_FILES = 50)
        WITH (ON_FAILURE = CONTINUE);
    ALTER SERVER AUDIT audit_vigilancia WITH (STATE = ON);
END
IF NOT EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'audit_spec_servidor')
BEGIN
    CREATE SERVER AUDIT SPECIFICATION audit_spec_servidor FOR SERVER AUDIT audit_vigilancia
        ADD (FAILED_LOGIN_GROUP), ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
        WITH (STATE = ON);
END
GO
USE DIRESA_LL_Vigilancia;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = N'audit_spec_vigilancia')
    CREATE DATABASE AUDIT SPECIFICATION audit_spec_vigilancia FOR SERVER AUDIT audit_vigilancia
        ADD (SELECT, INSERT, UPDATE, DELETE ON SCHEMA::vig BY [public]),
        ADD (SELECT, INSERT, UPDATE, DELETE ON SCHEMA::aud BY [public]),
        ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
        ADD (DATABASE_PERMISSION_CHANGE_GROUP),
        ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP)
        WITH (STATE = ON);
GO
-- Lectura del archivo de auditoría (rol auditor / DBA de seguridad):
-- SELECT event_time, action_id, succeeded, server_principal_name, object_name, statement
-- FROM sys.fn_get_audit_file(N'<<D:\SQLAudit\>>*.sqlaudit', DEFAULT, DEFAULT);

/* ---------- 9. CIFRADO EN REPOSO - TDE (Reglamento Ley 29733; ISO 27001 A.8.24) ---------- */
-- Requiere edición compatible (Enterprise, o Standard desde SQL Server 2019).
-- ADVERTENCIA: sin copia segura del certificado y su clave privada NO se podrá restaurar la base.
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<<CONTRASEÑA_MASTER_KEY>>';
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'cert_tde_vigilancia')
    CREATE CERTIFICATE cert_tde_vigilancia WITH SUBJECT = N'TDE DIRESA La Libertad - Vigilancia';
BACKUP CERTIFICATE cert_tde_vigilancia
    TO FILE = N'<<D:\Seguridad\cert_tde_vigilancia.cer>>'
    WITH PRIVATE KEY (FILE = N'<<D:\Seguridad\cert_tde_vigilancia.pvk>>',
                      ENCRYPTION BY PASSWORD = N'<<CONTRASEÑA_CLAVE_PRIVADA>>');
GO
USE DIRESA_LL_Vigilancia;
GO
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE cert_tde_vigilancia;
ALTER DATABASE DIRESA_LL_Vigilancia SET ENCRYPTION ON;
GO
-- Verificación (encryption_state = 3 -> cifrada):
SELECT DB_NAME(database_id) AS base, encryption_state, percent_complete, key_algorithm, key_length
FROM sys.dm_database_encryption_keys;
