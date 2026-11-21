/* =====================================================================
   SCRIPT   : 05_respaldo_restauracion.sql
   POLÍTICA PROPUESTA (documentada también en el informe, sección 3):
     - Modelo de recuperación: FULL (ya configurado en 01).
     - FULL         : domingo 01:00
     - DIFFERENTIAL : lunes a sábado 01:00 (acumula cambios desde el último FULL)
     - LOG          : cada 30 min (permite recuperación a un punto en el tiempo)
     - RPO objetivo : ≤ 30 min  |  RTO objetivo: ≤ 2 h   (objetivos propuestos; deben validarse con la DIRESA)
     - Retención    : 4 semanas en disco local + copia semanal fuera del servidor.
                      Si la copia externa se aloja fuera del Perú, aplicar art. 11 de la
                      Ley 29733 (nivel de protección adecuado en flujo transfronterizo).
     - Cada copia: WITH CHECKSUM, COMPRESSION; verificación RESTORE VERIFYONLY;
                   prueba de restauración completa mensual sobre una base _TEST.
   NOTA     : no ejecutado contra una instancia real al redactarlo. La columna
              "probado" del informe solo puede marcarse cuando usted ejecute la sección C
              y guarde la evidencia (aud.prueba_restauracion + capturas).
   ===================================================================== */
USE master;
GO
/* ---------- A. COPIAS DE SEGURIDAD (programar como pasos de SQL Server Agent) ---------- */
DECLARE @dir NVARCHAR(200) = N'<<D:\Backups\DIRESA_LL\>>';   -- carpeta con permisos solo para la cuenta del servicio
DECLARE @sello NVARCHAR(20) = FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmm');
DECLARE @archivo NVARCHAR(400);

-- A1. FULL (domingo)
SET @archivo = @dir + N'DIRESA_LL_Vigilancia_FULL_' + @sello + N'.bak';
BACKUP DATABASE DIRESA_LL_Vigilancia TO DISK = @archivo
    WITH INIT, CHECKSUM, COMPRESSION, STATS = 10, NAME = N'FULL semanal';
RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;
GO
-- A2. DIFFERENTIAL (lunes a sábado)
DECLARE @dir NVARCHAR(200) = N'<<D:\Backups\DIRESA_LL\>>';
DECLARE @archivo NVARCHAR(400) = @dir + N'DIRESA_LL_Vigilancia_DIFF_' + FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmm') + N'.bak';
BACKUP DATABASE DIRESA_LL_Vigilancia TO DISK = @archivo
    WITH DIFFERENTIAL, INIT, CHECKSUM, COMPRESSION, STATS = 10, NAME = N'DIFF diario';
RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;
GO
-- A3. LOG de transacciones (cada 30 minutos)
DECLARE @dir NVARCHAR(200) = N'<<D:\Backups\DIRESA_LL\>>';
DECLARE @archivo NVARCHAR(400) = @dir + N'DIRESA_LL_Vigilancia_LOG_' + FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmm') + N'.trn';
BACKUP LOG DIRESA_LL_Vigilancia TO DISK = @archivo
    WITH INIT, CHECKSUM, COMPRESSION, NAME = N'LOG 30 min';
GO
-- A4. (Opcional) cifrado de la copia, además de TDE: añada
--     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = cert_tde_vigilancia) a cada BACKUP.

-- Historial para el informe (qué copias existen y de qué tipo):
SELECT TOP (30) bs.database_name, bs.type AS tipo_D_I_L, bs.backup_start_date, bs.backup_finish_date,
       CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(12,2)) AS mb_comprimidos,
       bs.has_backup_checksums, bmf.physical_device_name
FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'DIRESA_LL_Vigilancia'
ORDER BY bs.backup_start_date DESC;
GO

/* ---------- B. TRABAJOS DE SQL SERVER AGENT (esquema a crear en SSMS o con msdb.dbo.sp_add_job) ----------
   Job "VIG_FULL"  : paso = A1 · programación semanal, domingo 01:00
   Job "VIG_DIFF"  : paso = A2 · programación semanal, lunes–sábado 01:00
   Job "VIG_LOG"   : paso = A3 · programación diaria, cada 30 minutos
   Job "VIG_LIMPIEZA": borra .bak/.trn con más de 28 días (tarea de mantenimiento) 
   Alertas: notificar por correo si cualquier job falla (operador DBA + oficial de seguridad). */

/* ---------- C. PRUEBA DE RESTAURACIÓN (ejecutar sobre una base de PRUEBA, nunca sobre producción) ---------- */
-- C0. Elegir los archivos más recientes (ajuste los nombres reales):
DECLARE @full NVARCHAR(400) = N'<<D:\Backups\DIRESA_LL\DIRESA_LL_Vigilancia_FULL_AAAAMMDD_HHMM.bak>>';
DECLARE @diff NVARCHAR(400) = N'<<D:\Backups\DIRESA_LL\DIRESA_LL_Vigilancia_DIFF_AAAAMMDD_HHMM.bak>>';

RESTORE HEADERONLY   FROM DISK = @full;     -- metadatos de la copia
RESTORE FILELISTONLY FROM DISK = @full;     -- nombres lógicos de archivos (por defecto: DIRESA_LL_Vigilancia y DIRESA_LL_Vigilancia_log)
RESTORE VERIFYONLY   FROM DISK = @full WITH CHECKSUM;
GO
-- C1. Restaurar FULL + DIFFERENTIAL (+ LOG) con otro nombre
--     (ajuste las rutas de MOVE a la carpeta de datos de su instancia)
DECLARE @t0 DATETIME2 = SYSDATETIME();
RESTORE DATABASE DIRESA_LL_Vigilancia_TEST
    FROM DISK = N'<<D:\Backups\DIRESA_LL\DIRESA_LL_Vigilancia_FULL_AAAAMMDD_HHMM.bak>>'
    WITH MOVE N'DIRESA_LL_Vigilancia'     TO N'<<D:\Data\DIRESA_LL_Vigilancia_TEST.mdf>>',
         MOVE N'DIRESA_LL_Vigilancia_log' TO N'<<D:\Data\DIRESA_LL_Vigilancia_TEST_log.ldf>>',
         NORECOVERY, REPLACE, STATS = 10;

RESTORE DATABASE DIRESA_LL_Vigilancia_TEST
    FROM DISK = N'<<D:\Backups\DIRESA_LL\DIRESA_LL_Vigilancia_DIFF_AAAAMMDD_HHMM.bak>>'
    WITH NORECOVERY, STATS = 10;

-- (Repita por cada .trn posterior, en orden cronológico.) Para volver a un instante concreto,
-- p. ej. justo antes de un DELETE accidental:
-- RESTORE LOG DIRESA_LL_Vigilancia_TEST FROM DISK = N'<<...LOG_AAAAMMDD_HHMM.trn>>'
--     WITH STOPAT = '2026-11-18T10:29:00', NORECOVERY;

RESTORE DATABASE DIRESA_LL_Vigilancia_TEST WITH RECOVERY;      -- deja la base utilizable
DECLARE @seg INT = DATEDIFF(SECOND, @t0, SYSDATETIME());
GO
-- C2. Verificación de integridad y de contenido
DBCC CHECKDB (DIRESA_LL_Vigilancia_TEST) WITH NO_INFOMSGS, ALL_ERRORMSGS;   -- sin salida = sin errores

DECLARE @o BIGINT = (SELECT COUNT_BIG(*) FROM DIRESA_LL_Vigilancia.vig.caso);
DECLARE @d BIGINT = (SELECT COUNT_BIG(*) FROM DIRESA_LL_Vigilancia_TEST.vig.caso);
SELECT @o AS filas_origen, @d AS filas_restauradas,
       CASE WHEN @o = @d THEN 'COINCIDE' ELSE 'REVISAR (¿hubo cambios tras la copia?)' END AS resultado;

-- C3. Guardar la evidencia (complete duracion_seg con la medida de @seg y checkdb_ok según DBCC)
INSERT DIRESA_LL_Vigilancia.aud.prueba_restauracion (tipo, base_destino, duracion_seg, filas_origen, filas_destino, checkdb_ok, observacion)
VALUES ('FULL+DIFF', N'DIRESA_LL_Vigilancia_TEST', NULL, @o, @d, NULL, N'Completar duración y resultado de DBCC tras la ejecución');
GO
-- C4. Limpiar la base de prueba
-- DROP DATABASE DIRESA_LL_Vigilancia_TEST;

/* ---------- D. ESCENARIO DE DESASTRE (guion para la defensa) ----------
   1) Alguien ejecuta DELETE vig.caso sin WHERE a las 10:30.  -> el trigger lo registra en aud.log_auditoria
      (usuario, host, hora) y permite fijar el instante exacto.
   2) Se toma BACKUP LOG de cola (BACKUP LOG ... WITH NORECOVERY) si la base sigue accesible.
   3) Se restaura FULL + DIFF + LOGs con STOPAT = 10:29 en una base _TEST, se valida y se
      reintegran los datos o se conmuta (RTO ≤ 2 h).  */
