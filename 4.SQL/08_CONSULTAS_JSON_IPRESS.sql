/* DATASALUD PERU - CONSULTAS DE DATOS SEMIESTRUCTURADOS
   Salida JSON del catalogo IPRESS oficial, util para intercambiar informacion
   con aplicaciones y servicios. No modifica los datos de origen.
   SQL Server 2016 o posterior.
*/
USE MINSA;
GO
-- Documentos JSON de establecimientos de salud del departamento seleccionado.
SELECT I.CODIGO_UNICO AS codigo, I.NOMBRE_ESTABLECIMIENTO AS establecimiento,
       I.DEPARTAMENTO AS departamento, I.PROVINCIA AS provincia,
       I.DISTRITO AS distrito, I.CATEGORIA AS categoria
FROM ref.IPRESS_MINSA AS I
WHERE I.DEPARTAMENTO = N'LA LIBERTAD'
ORDER BY I.CODIGO_UNICO
FOR JSON PATH, ROOT('ipress');
GO
-- Indicadores agregados SIS serializados en JSON.
SELECT S.ANO AS anio, S.MES AS mes, S.PROVINCIA AS provincia,
       S.DESC_SERVICIO AS servicio, SUM(S.ATENCIONES) AS total_atenciones
FROM dbo.ATENCIONES_SIS_OFICIAL AS S
GROUP BY S.ANO, S.MES, S.PROVINCIA, S.DESC_SERVICIO
ORDER BY S.ANO, S.MES, S.PROVINCIA, S.DESC_SERVICIO
FOR JSON PATH, ROOT('atenciones_sis');
GO
