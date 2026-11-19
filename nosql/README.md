# Tema 4: Nuevos paradigmas en el manejo de datos (MongoDB)

Proyecto: DataSalud Perú, CIIN1021P.
Base de datos: datasalud_nueva (MongoDB 8.3).

## Contenido

- tema4_mongodb.js: comandos de mongosh que generan y verifican la colección casos_mongo, y el CRUD sobre ella.
- evidencias/: capturas de la ejecución en mongosh.

## Fuente de datos

Datos abiertos del MINSA (datosabiertos.gob.pe), vigilancia de dengue y zoonosis 2000 a 2025.
Los CSV no se incluyen por su tamaño (118 MB y 13 MB).

## Pasos para reproducir

1. Limpiar las comillas de los CSV con limpiar.py y limpiar_zoonosis.py.
2. Importar con mongoimport:
   mongoimport --db datasalud_nueva --collection vigilancia --type csv --headerline --file dengue_limpio.csv
   mongoimport --db datasalud_nueva --collection vigilancia --type csv --headerline --file zoonosis_limpio.csv
3. Ejecutar el script:
   mongosh --file tema4_mongodb.js

## Resultados verificados

- vigilancia: 1 205 355 documentos.
- casos_mongo: 921 941 combinaciones.
  - DENGUE: 786 278 combinaciones y 1 065 262 casos.
  - ZOONOSIS: 135 663 combinaciones y 140 074 casos.
- Coinciden con dbo.caso en SQL Server.

## Diferencia declarada

El campo sexo conserva el valor N en MongoDB. SQL Server lo convierte en NULL con la función fn_sexo. El número de combinaciones y de casos no cambia.

## Comparación de latencia (consulta de La Libertad, 2024)

- MongoDB con índice departamento_1_ano_1, medido con toArray() y Date.now() e incluyendo el envío de filas: 382, 289 y 304 ms (promedio 325,0 ms).
- SQL Server con índice ix_dep_ano: promedio 295,3 ms (3 corridas, misma sesión).
