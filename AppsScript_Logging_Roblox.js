const SPREADSHEET_ID = "1UwOc262c9qrrzZW5wDuR9zL430n1tEOVpbqX9HhYuSo";

const SHEET_NAMES = {
  0: "raw_ping_sample",
  1: "raw_s1_status_objek",
  2: "raw_s2_posisi_objek",
  3: "raw_s3_status_global",
};

const HEADERS = {
  common: [
    "timestamp",
    "session_id",
    "scenario_id",
    "mechanism_type",
    "player_id",
    "player_count",
    "event_type",
    "player_ping_ms",
    "server_event_time",
    "client_receive_time",
  ],
  specific: {
    0: [],
    1: [
      "object_id",
      "object_type",
      "action_player_id",
      "server_object_status",
      "client_object_status",
      "server_spawn_time",
      "client_spawn_receive_time",
    ],
    2: [
      "object_id",
      "action_player_id",
      "server_pos_x",
      "server_pos_y",
      "server_pos_z",
      "client_pos_x",
      "client_pos_y",
      "client_pos_z",
    ],
    3: [
      "generator_id",
      "fuel_before",
      "fuel_after",
      "server_fuel_value",
      "client_fuel_value",
    ],
  },
};

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    const rows = Array.isArray(payload) ? payload : [payload];

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const grouped = { 0: [], 1: [], 2: [], 3: [] };

    for (const row of rows) {
      const sid = parseInt(row.scenario_id);
      
      // Guard: kalau scenario_id bukan 0/1/2/3, skip
      if (grouped[sid] === undefined) continue;

      // Guard: PingSample hanya boleh masuk ke sid=0
      if (row.event_type === "PingSample" && sid !== 0) {
        grouped[0].push(row);
        continue;
      }

      grouped[sid].push(row);
    }

    for (const [scenarioId, rowList] of Object.entries(grouped)) {
      if (rowList.length === 0) continue;
      const sheetName = SHEET_NAMES[scenarioId];
      const sheet = getOrCreateSheet(ss, sheetName, parseInt(scenarioId));
      appendRows(sheet, rowList, parseInt(scenarioId));
    }

    return ContentService.createTextOutput(
      JSON.stringify({ status: "ok", received: rows.length })
    ).setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService.createTextOutput(
      JSON.stringify({ status: "error", message: err.message })
    ).setMimeType(ContentService.MimeType.JSON);
  }
}

function getOrCreateSheet(ss, sheetName, scenarioId) {
  let sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    const fullHeader = [
      ...HEADERS.common,
      ...HEADERS.specific[scenarioId],
    ];
    sheet.appendRow(fullHeader);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, fullHeader.length).setFontWeight("bold");
  }
  return sheet;
}

function appendRows(sheet, rowList, scenarioId) {
  const fullHeader = [
    ...HEADERS.common,
    ...HEADERS.specific[scenarioId],
  ];

  const values = rowList.map((row) =>
    fullHeader.map((col) => {
      const val = row[col];
      return val !== undefined && val !== null ? val : "";
    })
  );

  if (values.length > 0) {
    sheet
      .getRange(sheet.getLastRow() + 1, 1, values.length, fullHeader.length)
      .setValues(values);
  }
}

function doGet(e) {
  return ContentService.createTextOutput(
    JSON.stringify({ status: "active", message: "Sheets receiver is running" })
  ).setMimeType(ContentService.MimeType.JSON);
}
