-- V3.8.0 Update_V3_MySQL.sql
-- SchemaVersion 3
--
-- Fix Issue #137 Power value too high for system size 
-- Fix Issue #283 SBFspot Upload Performance
-- 

ALTER TABLE Inverters
	MODIFY Serial INT UNSIGNED NOT NULL,
	MODIFY TimeStamp INT,
	MODIFY TotalPac INT,
    MODIFY EToday BIGINT,
	MODIFY ETotal BIGINT;
	ADD COLUMN PvoSystemSize INT UNSIGNED,
	ADD COLUMN PvoInstallDate VARCHAR(8);

--
-- vwInverters View
--
DROP VIEW IF EXISTS vwInverters;

CREATE View vwInverters AS
	SELECT Serial,
	Name,Type,SW_Version,
	From_UnixTime(TimeStamp) AS TimeStamp,
	TotalPac,
	EToday,ETotal,
	OperatingTime,FeedInTime,
	Status,GridRelay,
	Temperature,
	PvoSystemSize,
	PvoInstallDate
	FROM Inverters;

ALTER TABLE SpotData
	MODIFY Serial INT UNSIGNED NOT NULL,
	MODIFY TimeStamp INT NOT NULL,
	MODIFY Pdc1 INT,
	MODIFY Pdc2 INT,
	MODIFY Pac1 INT,
	MODIFY Pac2 INT,
	MODIFY Pac3 INT,
	MODIFY EToday BIGINT,
	MODIFY ETotal BIGINT;

ALTER TABLE DayData
	MODIFY Serial INT UNSIGNED NOT NULL,
	MODIFY TimeStamp INT NOT NULL,
	MODIFY TotalYield BIGINT,
	MODIFY Power BIGINT,
	MODIFY PVoutput TINYINT;

ALTER TABLE MonthData
	MODIFY Serial INT UNSIGNED NOT NULL,
	MODIFY TimeStamp INT NOT NULL,
	MODIFY TotalYield BIGINT,
	MODIFY DayYield BIGINT;

ALTER TABLE EventData
	MODIFY Serial INT UNSIGNED NOT NULL,
	MODIFY TimeStamp INT NOT NULL,
	MODIFY EntryID INT,
	MODIFY SusyID SMALLINT,
	MODIFY EventCode INT,
	MODIFY OldValue VARCHAR(64),
	MODIFY NewValue VARCHAR(64);

ALTER VIEW vwSpotData AS
    SELECT
		From_UnixTime(Dat.TimeStamp) AS TimeStamp,
		From_UnixTime(Dat.TimeStamp - (Dat.TimeStamp % 300)) AS Nearest5min,
		Inv.Name,
		Inv.Type,
		Dat.Serial,
		Pdc1, Pdc2,
		Idc1, Idc2,
		Udc1, Udc2,
		Pac1, Pac2, Pac3,
		Iac1, Iac2, Iac3,
		Uac1, Uac2, Uac3,
		Pdc1+Pdc2 AS PdcTot,
		Pac1+Pac2+Pac3 AS PacTot,
		CASE WHEN Pdc1+Pdc2 = 0 THEN
			0
		ELSE
			CASE WHEN Pdc1+Pdc2>Pac1+Pac2+Pac3 THEN
				ROUND((Pac1+Pac2+Pac3)/(Pdc1+Pdc2)*100,1)
			ELSE
				100.0
			END
		END AS Efficiency,
		Dat.EToday,
		Dat.ETotal,
		Frequency,
		Dat.OperatingTime,
		Dat.FeedInTime,
		ROUND(BT_Signal,1) AS BT_Signal,
		Dat.Status,
		Dat.GridRelay,
		ROUND(Dat.Temperature,1) AS Temperature
		FROM SpotData Dat
	INNER JOIN Inverters Inv ON Dat.Serial=Inv.Serial;

ALTER VIEW vwConsumption AS
	SELECT
		From_UnixTime(TimeStamp) As Timestamp,
		From_UnixTime(TimeStamp - (TimeStamp % 300)) AS Nearest5min,
		EnergyUsed,
		PowerUsed
	FROM Consumption;

--
-- vwPVODayData View
--
DROP VIEW IF EXISTS vwPVODayData;

CREATE VIEW vwPVODayData AS
	SELECT
		`TimeStamp`,
		`Serial`,
        `TotalYield`,
        `Power`
	FROM DayData Dat
    WHERE TimeStamp > unix_timestamp() -( SELECT `Value` FROM `Config` WHERE `Key` = 'Batch_DateLimit' ) * 86400 
		AND `PvOutput` IS NULL;

--
-- vwPVOSpotData View
--
DROP VIEW IF EXISTS vwPVOSpotData;

CREATE VIEW vwPVOSpotData AS
	SELECT
		`TimeStamp`,
		`TimeStamp` -( `TimeStamp` % 300 ) AS `Nearest5min`,
        `Serial`,
        `Pdc1`,
        `Pdc2`,
        `Idc1`,
        `Idc2`,
        `Udc1`,
		`Udc2`,
		`Pac1`,
        `Pac2`,
        `Pac3`,
        `Iac1`,
        `Iac2`,
        `Iac3`,
        `Uac1`,
        `Uac2`,
        `Uac3`,
        `Pdc1` + `Pdc2` AS `PdcTot`,
        `Pac1` + `Pac2` + `Pac3` AS `PacTot`,
        ROUND( `Temperature`, 1 ) AS `Temperature`
	FROM SpotData
    WHERE TimeStamp > unix_timestamp() -( SELECT `Value` FROM Config WHERE `Key` = 'Batch_DateLimit' ) * 86400;

--
-- vwPVOSpotDataAvg View
--
DROP VIEW IF EXISTS vwPVOSpotDataAvg;

CREATE VIEW vwPVOSpotDataAvg AS
	SELECT
		`nearest5min`,
		`serial`,
        avg( `Pdc1` ) AS `Pdc1`,
        avg( `Pdc2` ) AS `Pdc2`,
        avg( `Idc1` ) AS `Idc1`,
        avg( `Idc2` ) AS `Idc2`,
        avg( `Udc1` ) AS `Udc1`,
        avg( `Udc2` ) AS `Udc2`,
        avg( `Pac1` ) AS `Pac1`,
        avg( `Pac2` ) AS `Pac2`,
        avg( `Pac3` ) AS `Pac3`,
        avg( `Iac1` ) AS `Iac1`,
        avg( `Iac2` ) AS `Iac2`,
        avg( `Iac3` ) AS `Iac3`,
        avg( `Uac1` ) AS `Uac1`,
		avg( `Uac2` ) AS `Uac2`,
        avg( `Uac3` ) AS `Uac3`,
        avg( `Temperature` ) AS `Temperature`
	FROM vwPVOSpotData
    GROUP BY `serial`, `nearest5min`;

--
-- vwPVOUploadGeneration View
--
DROP VIEW IF EXISTS vwPVOUploadGeneration;

CREATE VIEW vwPVOUploadGeneration AS
	SELECT
		from_unixtime( dd.`TimeStamp` ) AS `TimeStamp`,
        dd.`Serial`,
        dd.`TotalYield` AS `V1`,
		CASE WHEN dd.Power > (IFNULL(inv.PvoSystemSize * 1.4, dd.Power))
			THEN 0 ELSE dd.Power END AS V2,
        NULL AS `V3`,
        NULL AS `V4`,
		CASE (SELECT `Value` FROM Config WHERE `Key` = 'PvoTemperature')
			WHEN 'Ambient' THEN NULL ELSE spot.Temperature END AS V5,
        spot.`Uac1` AS `V6`,
        NULL AS `V7`,
        NULL AS `V8`,
        NULL AS `V9`,
        NULL AS `V10`,
        NULL AS `V11`,
        NULL AS `V12`
	FROM vwPVODayData AS dd
    LEFT JOIN vwPVOSpotDataAvg AS spot ON dd.`Serial` = spot.`Serial` AND dd.`Timestamp` = spot.`Nearest5min`
	LEFT JOIN Inverters AS inv ON dd.Serial = inv.Serial;

-- Define temperature to show at PVoutput (V5): Inverter or Ambient
INSERT IGNORE INTO Config (`Key`,`Value`) VALUES ('PvoTemperature','Inverter');

-- Update SchemaVersion if all is OK
UPDATE Config SET `Value` = '3' WHERE `Key` = 'SchemaVersion';
