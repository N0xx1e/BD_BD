/* =====================================================================
   SCRIPT   : 06_rendimiento_indice.sql
   OBJETIVO : analizar el plan de ejecución de una consulta crítica, crear un índice y
              documentar métricas ANTES / DESPUÉS.
   CONSULTA CRÍTICA (requisito funcional RF-03): casos de dengue por provincia, distrito y
              semana epidemiológica de La Libertad en un año (tablero semanal de vigilancia).
   REFERENCIA : con ambos CSV cargados, esta consulta debe sumar 49 931 casos (dengue,
              La Libertad, 2024; calculado con pandas), repartidos así: TRUJILLO 35 203,
              ASCOPE 5 946, VIRU 5 730, PACASMAYO 1 798, CHEPEN 611, GRAN CHIMU 256,
              PATAZ 226, BOLIVAR 92, SANCHEZ CARRION 61, OTUZCO 7, SANTIAGO DE CHUCO 1.
   IMPORTANTE: las cifras de rendimiento NO se incluyen aquí porque dependen de su equipo y
              no fueron medidas. Ejecute el script y complete la tabla del informe (sección 3.4).
   ADVERTENCIA: DBCC DROPCLEANBUFFERS / FREEPROCCACHE solo en un entorno de PRUEBAS.
   ===================================================================== */
USE DIRESA_LL_Vigilancia;
GO

/* ---------- 0. Estado inicial: sin índices secundarios sobre vig.caso ---------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_caso_ano_ubigeo_semana' AND object_id = OBJECT_ID(N'vig.caso'))
    DROP INDEX IX_caso_ano_ubigeo_semana ON vig.caso;
GO
UPDATE STATISTICS vig.caso WITH FULLSCAN;
GO

/* ---------- 1. ANTES ---------- */
DBCC DROPCLEANBUFFERS;  DBCC FREEPROCCACHE;                  -- partida "en frío" y reproducible
SET STATISTICS IO ON;  SET STATISTICS TIME ON;
-- En SSMS active además "Incluir plan de ejecución real" (Ctrl+M) y guarde el .sqlplan.

SELECT u.provincia, u.distrito, c.semana, COUNT(*) AS casos
FROM vig.caso c
JOIN vig.ubigeo u ON u.ubigeo = c.ubigeo
WHERE c.ano = 2024
  AND c.ubigeo BETWEEN '130000' AND '139999'                 -- departamento La Libertad
  AND c.diagnostic IN ('A97.0','A97.1','A97.2')              -- dengue
GROUP BY u.provincia, u.distrito, c.semana
ORDER BY u.provincia, u.distrito, c.semana;

SET STATISTICS IO OFF;  SET STATISTICS TIME OFF;
-- Esperado en el plan "antes": Clustered Index Scan sobre vig.caso (lee toda la tabla).
-- Anote de la pestaña Messages: "logical reads" de 'caso', "CPU time", "elapsed time",
-- y del plan: operador principal y "Estimated Subtree Cost" del nodo raíz.
GO

/* ---------- 2. ÍNDICE ---------- 
   Clave (ano, ubigeo, semana): igualdad en ano -> rango de ubigeo -> agrupación por semana.
   INCLUDE diagnostic: el filtro de dengue se resuelve en el índice (índice "cubriente"; la
   consulta no necesita volver a la tabla). Costo: espacio adicional y algo más de tiempo en
   cargas masivas (se recomienda cargar y luego reconstruir). */
CREATE NONCLUSTERED INDEX IX_caso_ano_ubigeo_semana
    ON vig.caso (ano, ubigeo, semana)
    INCLUDE (diagnostic);
GO
UPDATE STATISTICS vig.caso WITH FULLSCAN;
GO

/* ---------- 3. DESPUÉS (misma consulta, mismas condiciones de partida) ---------- */
DBCC DROPCLEANBUFFERS;  DBCC FREEPROCCACHE;
SET STATISTICS IO ON;  SET STATISTICS TIME ON;

SELECT u.provincia, u.distrito, c.semana, COUNT(*) AS casos
FROM vig.caso c
JOIN vig.ubigeo u ON u.ubigeo = c.ubigeo
WHERE c.ano = 2024
  AND c.ubigeo BETWEEN '130000' AND '139999'
  AND c.diagnostic IN ('A97.0','A97.1','A97.2')
GROUP BY u.provincia, u.distrito, c.semana
ORDER BY u.provincia, u.distrito, c.semana;

SET STATISTICS IO OFF;  SET STATISTICS TIME OFF;
-- Esperado en el plan "después": Index Seek sobre IX_caso_ano_ubigeo_semana en lugar del Clustered Index Scan.
GO

/* ---------- 4. Tamaño del índice y uso (para el informe) ---------- */
SELECT i.name AS indice, CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS DECIMAL(12,2)) AS mb_usados
FROM sys.dm_db_partition_stats ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id = OBJECT_ID(N'vig.caso')
GROUP BY i.name;

SELECT i.name, s.user_seeks, s.user_scans, s.user_updates
FROM sys.dm_db_index_usage_stats s
JOIN sys.indexes i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.database_id = DB_ID() AND s.object_id = OBJECT_ID(N'vig.caso');
GO

/* ---------- 5. Tabla para completar en el informe ----------
   Métrica                              | Antes | Después | Mejora
   Operador de acceso a vig.caso        |  ...  |   ...   |
   Lecturas lógicas (vig.caso)          |  ...  |   ...   |
   Tiempo de CPU (ms)                   |  ...  |   ...   |
   Tiempo transcurrido (ms)             |  ...  |   ...   |
   Costo estimado del plan (subtree)    |  ...  |   ...   |
   Tamaño del índice (MB)               |   -   |   ...   |                                  */
