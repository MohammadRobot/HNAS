import 'package:flutter/material.dart';

/// Manual localizations class — no code generation required.
/// Supports English ('en') and Arabic ('ar') with full RTL layout.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
  ];

  bool get isRtl => locale.languageCode == 'ar';
  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  String _t(String key) {
    return _strings[locale.languageCode]?[key] ??
        _strings['en']![key] ??
        key;
  }

  // ── App ────────────────────────────────────────────────────────────────────
  String get appTitle => _t('appTitle');
  String get appFullName => _t('appFullName');
  String get appTagline => _t('appTagline');

  // ── Auth ───────────────────────────────────────────────────────────────────
  String get email => _t('email');
  String get emailRequired => _t('emailRequired');
  String get emailInvalid => _t('emailInvalid');
  String get password => _t('password');
  String get passwordRequired => _t('passwordRequired');
  String get signIn => _t('signIn');
  String get signingIn => _t('signingIn');
  String get signInWithGoogle => _t('signInWithGoogle');
  String get signOut => _t('signOut');
  String get signInTimeout => _t('signInTimeout');
  String get googleSignInTimeout => _t('googleSignInTimeout');
  String get unableToSignIn => _t('unableToSignIn');
  String get unableToSignInWithGoogle => _t('unableToSignInWithGoogle');
  String get googleSignInWebOnly => _t('googleSignInWebOnly');

  // ── Dashboard ──────────────────────────────────────────────────────────────
  String get dashboard => _t('dashboard');
  String get careOperations => _t('careOperations');
  String get newPatientIntake => _t('newPatientIntake');
  String get manageUsers => _t('manageUsers');
  String get patientDirectory => _t('patientDirectory');
  String get tapToOpenDetails => _t('tapToOpenDetails');
  String get refresh => _t('refresh');
  String get retry => _t('retry');
  String get addPatient => _t('addPatient');
  String get patientCreated => _t('patientCreated');
  String get unableToCreatePatient => _t('unableToCreatePatient');
  String get noPatients => _t('noPatients');

  // ── Roles ──────────────────────────────────────────────────────────────────
  String get roleAdmin => _t('roleAdmin');
  String get roleSupervisor => _t('roleSupervisor');
  String get roleNurse => _t('roleNurse');
  String get role => _t('role');

  String roleLabel(String r) {
    switch (r) {
      case 'admin':
        return roleAdmin;
      case 'supervisor':
        return roleSupervisor;
      case 'nurse':
        return roleNurse;
      default:
        return r;
    }
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  String get patients => _t('patients');
  String get done => _t('done');
  String get missed => _t('missed');
  String get late => _t('late');
  String get skipped => _t('skipped');

  // ── Patient detail tabs ────────────────────────────────────────────────────
  String get tabOverview => _t('tabOverview');
  String get tabMedications => _t('tabMedications');
  String get tabProcedures => _t('tabProcedures');
  String get tabLabTests => _t('tabLabTests');
  String get tabChecklist => _t('tabChecklist');
  String get tabHealthChecks => _t('tabHealthChecks');
  String get tabReports => _t('tabReports');
  String get tabAiAssistant => _t('tabAiAssistant');

  // ── Patient fields ─────────────────────────────────────────────────────────
  String get patient => _t('patient');
  String get active => _t('active');
  String get inactive => _t('inactive');
  String get timezone => _t('timezone');
  String get agency => _t('agency');
  String get riskFlags => _t('riskFlags');
  String get diagnosis => _t('diagnosis');
  String get dateOfBirth => _t('dateOfBirth');
  String get gender => _t('gender');
  String get phone => _t('phone');
  String get emergencyContact => _t('emergencyContact');
  String get address => _t('address');
  String get notes => _t('notes');
  String get allergies => _t('allergies');
  String get none => _t('none');
  String get notFound => _t('notFound');
  String get invalidPatientId => _t('invalidPatientId');

  // ── Users ──────────────────────────────────────────────────────────────────
  String get manageStaffUsers => _t('manageStaffUsers');

  // ── Language ───────────────────────────────────────────────────────────────
  String get language => _t('language');
  String get languageEnglish => _t('languageEnglish');
  String get languageArabic => _t('languageArabic');

  // ── Errors / notices ───────────────────────────────────────────────────────
  String get unableToLoadProfile => _t('unableToLoadProfile');
  String get unableToLoadCounts => _t('unableToLoadCounts');
  String get unableToLoadPatients => _t('unableToLoadPatients');
  String get noUserProfile => _t('noUserProfile');
  String get loading => _t('loading');

  // ── New-patient dialog ─────────────────────────────────────────────────────
  String get basicDetails => _t('basicDetails');
  String get contact => _t('contact');
  String get clinicalContext => _t('clinicalContext');
  String get fullName => _t('fullName');
  String get fullNameRequired => _t('fullNameRequired');
  String get cancel => _t('cancel');
  String get createPatient => _t('createPatient');

  // ── Health checks ──────────────────────────────────────────────────────────
  String get initialHealthCheck => _t('initialHealthCheck');
  String get noHealthChecks => _t('noHealthChecks');
  String get weightKg => _t('weightKg');
  String get temperatureC => _t('temperatureC');
  String get bloodPressure => _t('bloodPressure');
  String get pulseBpm => _t('pulseBpm');
  String get spo2 => _t('spo2');

  // ── Checklist ──────────────────────────────────────────────────────────────
  String get noChecklist => _t('noChecklist');
  String get generateChecklist => _t('generateChecklist');

  // ── AI assistant ───────────────────────────────────────────────────────────
  String get aiAssistant => _t('aiAssistant');
  String get typeMessage => _t('typeMessage');
  String get send => _t('send');

  // ── Misc ───────────────────────────────────────────────────────────────────
  String get save => _t('save');
  String get edit => _t('edit');
  String get delete => _t('delete');
  String get confirm => _t('confirm');
  String get today => _t('today');
  String get yesterday => _t('yesterday');
  String get noData => _t('noData');
  String get unknown => _t('unknown');

  // ══════════════════════════════════════════════════════════════════════════
  // Translation tables
  // ══════════════════════════════════════════════════════════════════════════
  static const Map<String, Map<String, String>> _strings = {
    'en': {
      // App
      'appTitle': 'HNAS',
      'appFullName': 'Home Nursing Assistant',
      'appTagline': 'Streamlining Patient Care',

      // Auth
      'email': 'Email',
      'emailRequired': 'Email is required.',
      'emailInvalid': 'Enter a valid email.',
      'password': 'Password',
      'passwordRequired': 'Password is required.',
      'signIn': 'Sign in',
      'signingIn': 'Signing in...',
      'signInWithGoogle': 'Sign in with Google',
      'signOut': 'Sign out',
      'signInTimeout':
          'Sign-in timed out. Ensure Firebase emulators are running and reachable.',
      'googleSignInTimeout':
          'Google sign-in timed out. Please try again.',
      'unableToSignIn': 'Unable to sign in.',
      'unableToSignInWithGoogle': 'Unable to sign in with Google.',
      'googleSignInWebOnly':
          'Google sign-in is available on web for this app build.',

      // Dashboard
      'dashboard': 'Dashboard',
      'careOperations': 'Care Operations',
      'newPatientIntake': 'New Patient Intake',
      'manageUsers': 'Manage Users',
      'patientDirectory': 'Patient Directory',
      'tapToOpenDetails': 'Tap a patient to open details',
      'refresh': 'Refresh',
      'retry': 'Retry',
      'addPatient': 'Add patient',
      'patientCreated': 'Patient created successfully.',
      'unableToCreatePatient': 'Unable to create patient',
      'noPatients': 'No patients available.',

      // Roles
      'roleAdmin': 'Admin',
      'roleSupervisor': 'Supervisor',
      'roleNurse': 'Nurse',
      'role': 'Role',

      // Stats
      'patients': 'Patients',
      'done': 'Done',
      'missed': 'Missed',
      'late': 'Late',
      'skipped': 'Skipped',

      // Tabs
      'tabOverview': 'Overview',
      'tabMedications': 'Medications',
      'tabProcedures': 'Procedures',
      'tabLabTests': 'Lab Tests',
      'tabChecklist': 'Checklist',
      'tabHealthChecks': 'Health Checks',
      'tabReports': 'Reports',
      'tabAiAssistant': 'AI Assistant',

      // Patient fields
      'patient': 'Patient',
      'active': 'Active',
      'inactive': 'Inactive',
      'timezone': 'Timezone',
      'agency': 'Agency',
      'riskFlags': 'Risk Flags',
      'diagnosis': 'Diagnosis',
      'dateOfBirth': 'Date of Birth',
      'gender': 'Gender',
      'phone': 'Phone',
      'emergencyContact': 'Emergency Contact',
      'address': 'Address',
      'notes': 'Notes',
      'allergies': 'Allergies',
      'none': 'None',
      'notFound': 'Patient not found.',
      'invalidPatientId': 'Invalid patient id.',

      // Users
      'manageStaffUsers': 'Manage Staff Users',

      // Language
      'language': 'Language',
      'languageEnglish': 'English',
      'languageArabic': 'العربية',

      // Errors
      'unableToLoadProfile': 'Unable to load user profile',
      'unableToLoadCounts': 'Unable to load counts',
      'unableToLoadPatients': 'Unable to load patients',
      'noUserProfile':
          'No user profile found. Seed demo data or create this document.',
      'loading': 'Loading...',

      // New patient dialog
      'basicDetails': 'Basic Details',
      'contact': 'Contact',
      'clinicalContext': 'Clinical Context',
      'fullName': 'Full Name',
      'fullNameRequired': 'Full name is required.',
      'cancel': 'Cancel',
      'createPatient': 'Create Patient',

      // Health checks
      'initialHealthCheck': 'Initial Health Check',
      'noHealthChecks': 'No health checks recorded.',
      'weightKg': 'Weight (kg)',
      'temperatureC': 'Temperature (°C)',
      'bloodPressure': 'Blood Pressure',
      'pulseBpm': 'Pulse (bpm)',
      'spo2': 'SpO₂ (%)',

      // Checklist
      'noChecklist': 'No checklist for today.',
      'generateChecklist': 'Generate Checklist',

      // AI
      'aiAssistant': 'AI Assistant',
      'typeMessage': 'Type a message...',
      'send': 'Send',

      // Misc
      'save': 'Save',
      'edit': 'Edit',
      'delete': 'Delete',
      'confirm': 'Confirm',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'noData': 'No data available.',
      'unknown': 'Unknown',
    },
    'ar': {
      // App
      'appTitle': 'HNAS',
      'appFullName': 'المساعد التمريضي المنزلي',
      'appTagline': 'تبسيط رعاية المرضى',

      // Auth
      'email': 'البريد الإلكتروني',
      'emailRequired': 'البريد الإلكتروني مطلوب.',
      'emailInvalid': 'أدخل بريدًا إلكترونيًا صحيحًا.',
      'password': 'كلمة المرور',
      'passwordRequired': 'كلمة المرور مطلوبة.',
      'signIn': 'تسجيل الدخول',
      'signingIn': 'جارٍ تسجيل الدخول...',
      'signInWithGoogle': 'تسجيل الدخول بـ Google',
      'signOut': 'تسجيل الخروج',
      'signInTimeout':
          'انتهت مهلة تسجيل الدخول. تأكد من تشغيل محاكيات Firebase.',
      'googleSignInTimeout':
          'انتهت مهلة تسجيل الدخول بـ Google. يرجى المحاولة مجددًا.',
      'unableToSignIn': 'تعذّر تسجيل الدخول.',
      'unableToSignInWithGoogle': 'تعذّر تسجيل الدخول بـ Google.',
      'googleSignInWebOnly': 'تسجيل الدخول بـ Google متاح على الويب فقط.',

      // Dashboard
      'dashboard': 'لوحة التحكم',
      'careOperations': 'عمليات الرعاية',
      'newPatientIntake': 'استقبال مريض جديد',
      'manageUsers': 'إدارة المستخدمين',
      'patientDirectory': 'دليل المرضى',
      'tapToOpenDetails': 'انقر على مريض لفتح التفاصيل',
      'refresh': 'تحديث',
      'retry': 'إعادة المحاولة',
      'addPatient': 'إضافة مريض',
      'patientCreated': 'تم إنشاء المريض بنجاح.',
      'unableToCreatePatient': 'تعذّر إنشاء المريض',
      'noPatients': 'لا يوجد مرضى.',

      // Roles
      'roleAdmin': 'مسؤول',
      'roleSupervisor': 'مشرف',
      'roleNurse': 'ممرض/ة',
      'role': 'الدور',

      // Stats
      'patients': 'المرضى',
      'done': 'مكتمل',
      'missed': 'فائت',
      'late': 'متأخر',
      'skipped': 'متخطى',

      // Tabs
      'tabOverview': 'نظرة عامة',
      'tabMedications': 'الأدوية',
      'tabProcedures': 'الإجراءات',
      'tabLabTests': 'تحاليل مخبرية',
      'tabChecklist': 'قائمة المهام',
      'tabHealthChecks': 'الفحوصات',
      'tabReports': 'التقارير',
      'tabAiAssistant': 'المساعد الذكي',

      // Patient fields
      'patient': 'المريض',
      'active': 'نشط',
      'inactive': 'غير نشط',
      'timezone': 'المنطقة الزمنية',
      'agency': 'الوكالة',
      'riskFlags': 'علامات الخطر',
      'diagnosis': 'التشخيص',
      'dateOfBirth': 'تاريخ الميلاد',
      'gender': 'الجنس',
      'phone': 'الهاتف',
      'emergencyContact': 'جهة الاتصال الطارئ',
      'address': 'العنوان',
      'notes': 'ملاحظات',
      'allergies': 'الحساسية',
      'none': 'لا شيء',
      'notFound': 'المريض غير موجود.',
      'invalidPatientId': 'معرّف المريض غير صالح.',

      // Users
      'manageStaffUsers': 'إدارة موظفي الرعاية',

      // Language
      'language': 'اللغة',
      'languageEnglish': 'English',
      'languageArabic': 'العربية',

      // Errors
      'unableToLoadProfile': 'تعذّر تحميل ملف المستخدم',
      'unableToLoadCounts': 'تعذّر تحميل الأرقام',
      'unableToLoadPatients': 'تعذّر تحميل المرضى',
      'noUserProfile':
          'لم يتم العثور على ملف المستخدم. أضف بيانات تجريبية أو أنشئ هذا المستند.',
      'loading': 'جارٍ التحميل...',

      // New patient dialog
      'basicDetails': 'التفاصيل الأساسية',
      'contact': 'التواصل',
      'clinicalContext': 'السياق الطبي',
      'fullName': 'الاسم الكامل',
      'fullNameRequired': 'الاسم الكامل مطلوب.',
      'cancel': 'إلغاء',
      'createPatient': 'إنشاء مريض',

      // Health checks
      'initialHealthCheck': 'الفحص الصحي الأولي',
      'noHealthChecks': 'لا توجد فحوصات صحية مسجّلة.',
      'weightKg': 'الوزن (كغ)',
      'temperatureC': 'الحرارة (°م)',
      'bloodPressure': 'ضغط الدم',
      'pulseBpm': 'النبض (نبضة/دقيقة)',
      'spo2': 'تشبع الأكسجين (%)',

      // Checklist
      'noChecklist': 'لا توجد قائمة مهام لليوم.',
      'generateChecklist': 'إنشاء قائمة المهام',

      // AI
      'aiAssistant': 'المساعد الذكي',
      'typeMessage': 'اكتب رسالة...',
      'send': 'إرسال',

      // Misc
      'save': 'حفظ',
      'edit': 'تعديل',
      'delete': 'حذف',
      'confirm': 'تأكيد',
      'today': 'اليوم',
      'yesterday': 'أمس',
      'noData': 'لا توجد بيانات.',
      'unknown': 'غير معروف',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
