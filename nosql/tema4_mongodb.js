use datasalud_nueva

db.vigilancia.countDocuments({})

db.vigilancia.aggregate([
  { $match: { ano: { $gte: 2000, $lte: 2026 }, semana: { $gte: 1, $lte: 53 }, edad: { $gte: 0, $lte: 120 } } },
  { $group: { _id: { origen: { $cond: [ { $regexMatch: { input: "$enfermedad", regex: "^DENGUE" } }, "DENGUE", "ZOONOSIS" ] }, departamento: "$departamento", provincia: "$provincia", distrito: "$distrito", enfermedad: "$enfermedad", ano: "$ano", semana: "$semana", edad: "$edad", sexo: "$sexo" }, casos: { $sum: 1 } } },
  { $project: { _id: 0, origen: "$_id.origen", departamento: "$_id.departamento", provincia: "$_id.provincia", distrito: "$_id.distrito", enfermedad: "$_id.enfermedad", ano: "$_id.ano", semana: "$_id.semana", edad: "$_id.edad", sexo: "$_id.sexo", casos: 1 } },
  { $out: "casos_mongo" }
], { allowDiskUse: true })

db.casos_mongo.countDocuments({})
db.casos_mongo.aggregate([{ $group: { _id: "$origen", combinaciones: { $sum: 1 }, total_casos: { $sum: "$casos" } } }])

db.casos_mongo.insertOne({ origen: "PRUEBA", departamento: "LA LIBERTAD", provincia: "TRUJILLO", distrito: "TRUJILLO", enfermedad: "PRUEBA", ano: 2024, semana: 10, edad: 30, sexo: "F", casos: 1 })
db.casos_mongo.aggregate([{ $match: { origen: "DENGUE", departamento: "LA LIBERTAD", ano: 2024 } }, { $group: { _id: "$provincia", casos: { $sum: "$casos" } } }, { $sort: { casos: -1 } }])
db.casos_mongo.updateOne({ origen: "PRUEBA" }, { $set: { revisado: true } })
db.casos_mongo.deleteMany({ origen: "PRUEBA" })
db.casos_mongo.countDocuments({ origen: "PRUEBA" })
