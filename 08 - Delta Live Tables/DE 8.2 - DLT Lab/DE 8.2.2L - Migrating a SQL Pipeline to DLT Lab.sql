-- Databricks notebook source
-- MAGIC %md-sandbox
-- MAGIC
-- MAGIC <div style="text-align: center; line-height: 0; padding-top: 9px;">
-- MAGIC   <img src="https://databricks.com/wp-content/uploads/2018/03/db-academy-rgb-1200px.png" alt="Databricks Learning" style="width: 600px">
-- MAGIC </div>

-- COMMAND ----------

-- MAGIC %md <i18n value="cffedc4f-a6a4-4412-8193-46a7a8a6a213"/>
-- MAGIC
-- MAGIC
-- MAGIC # Lab: Migrating a SQL Pipeline to Delta Live Tables
-- MAGIC
-- MAGIC This notebook will be completed by you to implement a DLT pipeline using SQL. 
-- MAGIC
-- MAGIC It is **not intended** to be executed interactively, but rather to be deployed as a pipeline once you have completed your changes.
-- MAGIC
-- MAGIC To aid in completion of this Notebook, please refer to the <a href="https://docs.databricks.com/data-engineering/delta-live-tables/delta-live-tables-language-ref.html#sql" target="_blank">DLT syntax documentation</a>.

-- COMMAND ----------

-- MAGIC %md <i18n value="01e06565-56e7-4581-8833-14bc0db8c281"/>
-- MAGIC
-- MAGIC
-- MAGIC ## Declare Bronze Table
-- MAGIC
-- MAGIC Declare a bronze table, **`recordings_bronze`**, that ingests JSON data incrementally (using Auto Loader) from the simulated cloud source. The source location is already supplied as an argument; using this value is illustrated in the cell below.
-- MAGIC
-- MAGIC As we did previously, include two additional columns:
-- MAGIC * **`receipt_time`** that records a timestamp as returned by **`current_timestamp()`** 
-- MAGIC * **`source_file`** that is obtained by **`input_file_name()`**

-- COMMAND ----------

CREATE OR REFRESH STREAMING LIVE TABLE recordings_bronze
AS SELECT 
  *,
  current_timestamp() AS receipt_time,
  input_file_name() AS source_file
  FROM cloud_files("${source}", "json", map("cloudFiles.schemaHints", "time DOUBLE, mrn INTEGER"))

-- COMMAND ----------

-- MAGIC %md <i18n value="57422f74-b830-4abb-b4a9-969d0ab90be6"/>
-- MAGIC
-- MAGIC
-- MAGIC ### PII File
-- MAGIC
-- MAGIC Using a similar CTAS syntax, create a live **table** into the CSV data found in the *healthcare/patient* dataset.
-- MAGIC
-- MAGIC To properly configure Auto Loader for this source, you will need to specify the following additional parameters:
-- MAGIC
-- MAGIC | option | value |
-- MAGIC | --- | --- |
-- MAGIC | **`header`** | **`true`** |
-- MAGIC | **`cloudFiles.inferColumnTypes`** | **`true`** |
-- MAGIC
-- MAGIC <img src="https://files.training.databricks.com/images/icon_note_24.png"/> Auto Loader configurations for CSV can be found <a href="https://docs.databricks.com/spark/latest/structured-streaming/auto-loader-csv.html" target="_blank">here</a>.

-- COMMAND ----------

CREATE OR REFRESH STREAMING LIVE TABLE  pii
AS SELECT *
  FROM cloud_files("${datasets_path}/healthcare/patient", "csv", map("header", "true", "cloudFiles.inferColumnTypes", "true"))

-- COMMAND ----------

-- MAGIC %md <i18n value="3573b6a4-233a-4f23-a002-aab072eb5096"/>
-- MAGIC
-- MAGIC
-- MAGIC ## Declare Silver Tables
-- MAGIC
-- MAGIC Our silver table, **`recordings_enriched`**, will consist of the following fields:
-- MAGIC
-- MAGIC | Field | Type |
-- MAGIC | --- | --- |
-- MAGIC | **`device_id`** | **`INTEGER`** |
-- MAGIC | **`mrn`** | **`LONG`** |
-- MAGIC | **`heartrate`** | **`DOUBLE`** |
-- MAGIC | **`time`** | **`TIMESTAMP`** (example provided below) |
-- MAGIC | **`name`** | **`STRING`** |
-- MAGIC
-- MAGIC This query should also enrich the data through an inner join with the **`pii`** table on the common **`mrn`** field to obtain the name.
-- MAGIC
-- MAGIC Implement quality control by applying a constraint to drop records with an invalid **`heartrate`** (that is, not greater than zero).

-- COMMAND ----------

CREATE OR REFRESH STREAMING LIVE TABLE recordings_enriched
  (CONSTRAINT positive_heartrate EXPECT (heartrate > 0) ON VIOLATION DROP ROW)
AS SELECT 
  CAST(r.device_id AS INTEGER) device_id, 
  CAST(r.mrn AS LONG) mrn, 
  CAST(r.heartrate AS DOUBLE) heartrate, 
  CAST(FROM_UNIXTIME(DOUBLE(time), 'yyyy-MM-dd HH:mm:ss') AS TIMESTAMP) time,
  p.name
  FROM
     STREAM(LIVE.recordings_bronze) r
     INNER JOIN STREAM(LIVE.pii) p ON p.mrn = r.mrn

-- COMMAND ----------

-- MAGIC %md <i18n value="3b9309a8-9e1d-46a2-a0eb-e95fe698d23b"/>
-- MAGIC
-- MAGIC
-- MAGIC ## Gold Table
-- MAGIC
-- MAGIC Create a gold table, **`daily_patient_avg`**, that aggregates **`recordings_enriched`** by **`mrn`**, **`name`**, and **`date`** and delivers the following columns:
-- MAGIC
-- MAGIC | Column name | Value |
-- MAGIC | --- | --- |
-- MAGIC | **`mrn`** | **`mrn`** from source |
-- MAGIC | **`name`** | **`name`** from source |
-- MAGIC | **`avg_heartrate`** | Average **`heartrate`** from the grouping |
-- MAGIC | **`date`** | Date extracted from **`time`** |

-- COMMAND ----------

CREATE OR REFRESH STREAMING LIVE TABLE daily_patient_avg
  COMMENT "Daily mean heartrate by patient"
AS SELECT
  mrn,
  name,
  DATE(time) `date`,
  MEAN(heartrate) avg_heartrate
FROM
  STREAM(LIVE.recordings_enriched)
GROUP BY mrn, name, DATE(time)

-- COMMAND ----------

-- MAGIC %md-sandbox
-- MAGIC &copy; 2022 Databricks, Inc. All rights reserved.<br/>
-- MAGIC Apache, Apache Spark, Spark and the Spark logo are trademarks of the <a href="https://www.apache.org/">Apache Software Foundation</a>.<br/>
-- MAGIC <br/>
-- MAGIC <a href="https://databricks.com/privacy-policy">Privacy Policy</a> | <a href="https://databricks.com/terms-of-use">Terms of Use</a> | <a href="https://help.databricks.com/">Support</a>
