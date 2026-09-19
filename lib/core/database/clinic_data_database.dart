import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Owns the SQLite connection for whichever clinic is currently active —
/// patients and visits, one separate file per clinic, so switching clinics
/// means literally opening a different file rather than filtering rows.
///
/// This is what makes "عيادتين، كل وحدة بقاعدة بيانات منفصلة" (two clinics,
/// each with its own separate database) literally true rather than the
/// clinic_id-scoped single-file multi-tenancy the app started with.
class ClinicDataDatabase {
  ClinicDataDatabase._();

  static final ClinicDataDatabase instance = ClinicDataDatabase._();

  static const _schemaVersion = 9;

  /// The eye-clinic exam rows this app shipped with before exam fields
  /// became doctor-configurable — seeded into every new clinic so existing
  /// behavior doesn't change out of the box; a clinic for another
  /// specialty can edit/replace these from Admin > قوالب الفحص.
  static const _defaultExamFieldLabels = [
    'Auto',
    'Cycl/Myder',
    'Old. Glass',
    'Pers.Refract',
    'Near',
    'Anter.S',
    'Lens',
    'Poster.S',
  ];

  /// Of the default rows above, the three that hold descriptive clinical
  /// findings rather than a short refraction number — seeded (and, on
  /// upgrade, retroactively flagged) with [isLongText] so their input gets
  /// a multi-line box that can actually fit a sentence.
  static const _defaultLongTextLabels = ['Anter.S', 'Lens', 'Poster.S'];

  Database? _db;
  String? _openDbFileName;

  /// The clinic data file currently open, if any (null before a clinic has
  /// been selected — e.g. mid-onboarding).
  String? get activeDbFileName => _openDbFileName;

  /// Full path to the active clinic's file on disk — used by
  /// ClinicBackupService to copy/restore it.
  Future<String?> activeFilePath() async {
    if (_openDbFileName == null) return null;
    final folder = await AppDatabase.instance.currentFolder();
    return p.join(folder, _openDbFileName!);
  }

  /// Closes the active connection so its file can be safely overwritten
  /// (restoring a backup) — callers must [switchTo] again afterwards.
  Future<void> closeActive() async {
    await _db?.close();
    _db = null;
    _openDbFileName = null;
  }

  /// Opens [dbFileName] (creating it if new), closing whichever clinic's
  /// file was open before. A no-op if it's already the active one, so
  /// re-selecting the same clinic doesn't drop in-flight queries.
  Future<void> switchTo(String dbFileName) async {
    if (_openDbFileName == dbFileName && _db != null) return;

    await _db?.close();
    _db = null;

    final folder = await AppDatabase.instance.currentFolder();
    final path = p.join(folder, dbFileName);

    _db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    await _ensureExamFieldsSeeded(_db!);
    _openDbFileName = dbFileName;
  }

  /// The active clinic's connection. Throws if [switchTo] hasn't been
  /// called yet — callers (repositories) should only run after a clinic is
  /// selected, which AppShell/activeClinicProvider guarantee.
  Future<Database> get database async {
    if (_db == null) {
      throw StateError(
        'ClinicDataDatabase.switchTo() must be called before use — no clinic is active yet.',
      );
    }
    return _db!;
  }

  Future<void> _createSchema(Database db, int version) async {
    // Same shape as the old single-file schema, minus clinic_id: the file
    // itself is the clinic boundary now, so there's nothing left to scope.
    await db.execute('''
      CREATE TABLE patients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_number TEXT,
        full_name TEXT NOT NULL,
        gender TEXT,
        phone TEXT,
        address TEXT,
        birth_date TEXT,
        age INTEGER,
        diagnosis TEXT,
        previous_medications TEXT,
        current_medications TEXT,
        allergies TEXT,
        medical_history TEXT,
        surgeries_history TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(patient_number)
      )
    ''');

    await db.execute(
      'CREATE INDEX patients_full_name_index ON patients (full_name)',
    );
    await db.execute('CREATE INDEX patients_phone_index ON patients (phone)');
    await db.execute(
      'CREATE INDEX patients_patient_number_index ON patients (patient_number)',
    );
    await db.execute(
      'CREATE INDEX patients_is_active_created_index ON patients (is_active, created_at)',
    );

    await db.execute('''
      CREATE TABLE visits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
        visit_date TEXT NOT NULL,
        auto_od TEXT,
        auto_os TEXT,
        cycl_myder_od TEXT,
        cycl_myder_os TEXT,
        old_glass_od TEXT,
        old_glass_os TEXT,
        pers_refract_od TEXT,
        pers_refract_os TEXT,
        near_od TEXT,
        near_os TEXT,
        anter_s_od TEXT,
        anter_s_os TEXT,
        lens_od TEXT,
        lens_os TEXT,
        poster_s_od TEXT,
        poster_s_os TEXT,
        notes TEXT,
        needs_follow_up INTEGER NOT NULL DEFAULT 0,
        follow_up_by TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX visits_patient_date_index ON visits (patient_id, visit_date)',
    );
    await db.execute(
      'CREATE INDEX visits_needs_follow_up_index ON visits (needs_follow_up)',
    );

    await _createAppointmentsTable(db);
    await _createClinicSettingsTable(db);
    await _createVisitPhotosTable(db);
    await _createExamFieldTables(db);
    await _seedDefaultExamFields(db);
    await _createActivityLogTable(db);
  }

  /// Who did what and when — the accountability multiple staff accounts
  /// need (see ActivityLogService). `actor_user_id`/`actor_name` are a
  /// snapshot, not a foreign key: the acting user's row lives in the
  /// app-level database (see AppDatabase), a different file this one can't
  /// join against, and keeping the name here means an entry still reads
  /// correctly even if that account is later deleted.
  Future<void> _createActivityLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE activity_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor_user_id INTEGER,
        actor_name TEXT NOT NULL,
        action TEXT NOT NULL,
        entity_label TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX activity_log_created_at_index ON activity_log (created_at)',
    );
  }

  /// Doctor-configurable exam form — replaces the old fixed OD/OS columns
  /// on `visits` so the app works for any specialty, not just ophthalmology.
  /// `exam_field_templates` is the clinic's current form definition (edited
  /// from Admin); `visit_field_values` holds what was actually entered for
  /// one visit against one template row, with `side` distinguishing a
  /// paired reading (e.g. right/left eye) from a single value.
  Future<void> _createExamFieldTables(Database db) async {
    await db.execute('''
      CREATE TABLE exam_field_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        has_sides INTEGER NOT NULL DEFAULT 0,
        is_long_text INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE visit_field_values (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
        template_id INTEGER NOT NULL REFERENCES exam_field_templates(id) ON DELETE CASCADE,
        side TEXT NOT NULL DEFAULT 'single',
        value TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX visit_field_values_visit_index ON visit_field_values (visit_id)',
    );
    await db.execute(
      'CREATE INDEX visit_field_values_template_index ON visit_field_values (template_id)',
    );
  }

  /// Reseeds the default eye-clinic exam fields whenever a clinic's form
  /// turns up completely empty on open — a doctor should never land on a
  /// blank "add every field yourself" screen, whether that's a fresh
  /// install, a migration edge case, or the last field having been deleted
  /// from Admin > قوالب الفحص. Never touches a form that already has any
  /// rows, including one deliberately narrowed to a single custom field —
  /// this only fills a genuinely empty form.
  Future<void> _ensureExamFieldsSeeded(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM exam_field_templates',
    );
    final count = rows.first['c']! as int;
    if (count == 0) {
      await _seedDefaultExamFields(db);
    }
  }

  Future<void> _seedDefaultExamFields(Database db) async {
    for (var i = 0; i < _defaultExamFieldLabels.length; i++) {
      final label = _defaultExamFieldLabels[i];
      await db.insert('exam_field_templates', {
        'label': label,
        'has_sides': 1,
        'is_long_text': _defaultLongTextLabels.contains(label) ? 1 : 0,
        'sort_order': i,
      });
    }
  }

  /// Copies data out of the old fixed OD/OS columns on `visits` into
  /// `visit_field_values` rows against the just-seeded default templates,
  /// so upgrading doesn't lose exam data already on file. The old columns
  /// themselves are left in place (unused) rather than dropped — SQLite's
  /// DROP COLUMN support varies by version, and there's no need to risk it
  /// for columns that just sit there empty from now on.
  Future<void> _migrateFixedExamColumnsToTemplates(Database db) async {
    final templateRows = await db.query(
      'exam_field_templates',
      orderBy: 'sort_order ASC',
    );
    final templateIds = [for (final row in templateRows) row['id']! as int];

    const columnPairs = [
      ('auto_od', 'auto_os'),
      ('cycl_myder_od', 'cycl_myder_os'),
      ('old_glass_od', 'old_glass_os'),
      ('pers_refract_od', 'pers_refract_os'),
      ('near_od', 'near_os'),
      ('anter_s_od', 'anter_s_os'),
      ('lens_od', 'lens_os'),
      ('poster_s_od', 'poster_s_os'),
    ];

    final visits = await db.query('visits');
    final batch = db.batch();
    for (final visit in visits) {
      final visitId = visit['id']! as int;
      for (var i = 0; i < columnPairs.length && i < templateIds.length; i++) {
        final (rightColumn, leftColumn) = columnPairs[i];
        final templateId = templateIds[i];
        final rightValue = visit[rightColumn] as String?;
        final leftValue = visit[leftColumn] as String?;

        if (rightValue != null && rightValue.trim().isNotEmpty) {
          batch.insert('visit_field_values', {
            'visit_id': visitId,
            'template_id': templateId,
            'side': 'right',
            'value': rightValue,
          });
        }
        if (leftValue != null && leftValue.trim().isNotEmpty) {
          batch.insert('visit_field_values', {
            'visit_id': visitId,
            'template_id': templateId,
            'side': 'left',
            'value': leftValue,
          });
        }
      }
    }
    await batch.commit(noResult: true);
  }

  /// Photos attached to a visit (eye photos, old prescriptions) — stored
  /// as BLOBs in the same file as everything else so they travel with a
  /// clinic's regular backup/restore (see ClinicBackupService) instead of
  /// needing a separate photos folder to keep in sync with it.
  Future<void> _createVisitPhotosTable(Database db) async {
    await db.execute('''
      CREATE TABLE visit_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
        image_data BLOB NOT NULL,
        created_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX visit_photos_visit_index ON visit_photos (visit_id)',
    );
  }

  Future<void> _createAppointmentsTable(Database db) async {
    // Future-dated bookings — distinct from `visits`, which is the
    // historical exam record filled in after the patient is actually seen.
    // `type` (consultation/followUp) decides whether payment is owed — see
    // AppointmentType.requiresPayment — checked against `clinic_settings`'
    // follow-up window when a nurse books a new appointment.
    await db.execute('''
      CREATE TABLE appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
        scheduled_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'scheduled',
        type TEXT NOT NULL DEFAULT 'consultation',
        notes TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX appointments_scheduled_at_index ON appointments (scheduled_at)',
    );
    await db.execute(
      'CREATE INDEX appointments_patient_index ON appointments (patient_id)',
    );
    await db.execute(
      'CREATE INDEX appointments_patient_type_index ON appointments (patient_id, type, scheduled_at)',
    );
  }

  /// A single-row table of clinic-wide policy knobs that aren't tied to any
  /// one patient/visit/appointment — how many days after a paid
  /// consultation a follow-up stays free (`follow_up_days`), and how many
  /// further days after that a re-check is still discounted to half price
  /// (`half_price_days`) before it counts as a fresh consultation again.
  /// Nurses set both from the Appointments page, not locked behind Admin,
  /// since it's their call day to day (see AppointmentRepository
  /// .setFollowUpDays / .setHalfPriceDays).
  Future<void> _createClinicSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE clinic_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        follow_up_days INTEGER NOT NULL DEFAULT 30,
        half_price_days INTEGER NOT NULL DEFAULT 60
      )
    ''');
    await db.insert('clinic_settings', {
      'id': 1,
      'follow_up_days': 30,
      'half_price_days': 60,
    });
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createAppointmentsTable(db);
    }
    if (oldVersion < 3) {
      if (oldVersion >= 2) {
        // The table already exists from version 2 — add the new column
        // rather than recreating it, so existing bookings aren't lost.
        await db.execute(
          "ALTER TABLE appointments ADD COLUMN type TEXT NOT NULL DEFAULT 'consultation'",
        );
      }
      await _createClinicSettingsTable(db);
    }
    if (oldVersion < 4) {
      await _createVisitPhotosTable(db);
    }
    if (oldVersion < 5) {
      await _createExamFieldTables(db);
      await _seedDefaultExamFields(db);
      await _migrateFixedExamColumnsToTemplates(db);
    }
    if (oldVersion < 6) {
      await _createActivityLogTable(db);
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE exam_field_templates ADD COLUMN is_long_text INTEGER NOT NULL DEFAULT 0',
      );
      // Retroactively flag the same three default rows _seedDefaultExamFields
      // would flag on a fresh install, so an existing clinic gets the bigger
      // input box too without having to find and toggle it by hand.
      for (final label in _defaultLongTextLabels) {
        await db.update(
          'exam_field_templates',
          {'is_long_text': 1},
          where: 'label = ?',
          whereArgs: [label],
        );
      }
    }
    if (oldVersion < 8) {
      // Only if clinic_settings already existed pre-upgrade (created
      // starting at version 3) — an oldVersion < 3 upgrade just created it
      // fresh above, already with this column, so altering it again here
      // would fail with "duplicate column name".
      if (oldVersion >= 3) {
        await db.execute(
          'ALTER TABLE clinic_settings ADD COLUMN half_price_days INTEGER NOT NULL DEFAULT 60',
        );
      }
    }
    if (oldVersion < 9) {
      // `visits` has existed since version 1, so no existence guard is
      // needed the way clinic_settings above needed one.
      await db.execute(
        'ALTER TABLE visits ADD COLUMN needs_follow_up INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE visits ADD COLUMN follow_up_by TEXT');
      await db.execute(
        'CREATE INDEX visits_needs_follow_up_index ON visits (needs_follow_up)',
      );
    }
  }
}
