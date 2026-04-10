export type EntityId = string;
export type IsoDateTimeString = string;
export type DateId = string; // YYYY-MM-DD

export type UserRole =
  | 'admin'
  | 'supervisor'
  | 'nurse'
  | 'clinician'
  | 'caregiver'
  | 'viewer';

export interface User {
  id: EntityId;
  email: string;
  displayName: string;
  role: UserRole;
  patientIds: EntityId[];
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

export interface Medicine {
  id: EntityId;
  patientId: EntityId;
  name: string;
  form: 'tablet' | 'capsule' | 'liquid' | 'injection' | 'other';
  doseAmount: number;
  doseUnit: string;
  instructions?: string;
  startDate?: DateId;
  recurrenceMode?: 'daily' | 'interval';
  recurrenceEvery?: number;
  recurrenceUnit?: 'days' | 'weeks' | 'months';
  active: boolean;
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

export interface Procedure {
  id: EntityId;
  patientId: EntityId;
  name: string;
  instructions: string;
  frequency: 'once' | 'daily' | 'weekly' | 'as_needed';
  active: boolean;
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

export interface BasalRateSegment {
  startTime: string; // HH:mm
  unitsPerHour: number;
}

export interface InsulinProfileRapid {
  type: 'rapid';
  id: EntityId;
  label: string;
  insulinName: string;
  carbRatioGramsPerUnit: number;
  correctionFactorMgDlPerUnit: number;
  targetGlucoseMgDl: number;
  active: boolean;
}

export interface InsulinProfileBasal {
  type: 'basal';
  id: EntityId;
  label: string;
  insulinName: string;
  schedule: BasalRateSegment[];
  active: boolean;
}

export type InsulinProfile = InsulinProfileRapid | InsulinProfileBasal;

export interface Patient {
  id: EntityId;
  fullName: string;
  dateOfBirth?: DateId;
  gender?: 'male' | 'female' | 'other' | 'prefer_not_to_say';
  phoneNumber?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;
  address?: string;
  notes?: string;
  riskFlags?: string[];
  diagnosis?: string[];
  allergies?: string[];
  timezone: string;
  active: boolean;
  primaryCaregiverUserId?: EntityId;
  insulinProfiles: InsulinProfile[];
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

export interface HealthCheck {
  id: EntityId;
  patientId: EntityId;
  dateId: DateId;
  checkedAt: IsoDateTimeString;
  weightKg?: number;
  temperatureC?: number;
  bloodPressureSystolic?: number;
  bloodPressureDiastolic?: number;
  pulseBpm?: number;
  spo2Pct?: number;
  notes?: string;
  recordedByUid?: EntityId;
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

export interface LabTest {
  id: EntityId;
  patientId: EntityId;
  testName: string;
  panel?: string;
  scheduleDate?: DateId;
  scheduleTime?: string;
  status: 'scheduled' | 'in_progress' | 'completed' | 'cancelled';
  priority?: string;
  orderedBy?: string;
  notes?: string;
  resultValue?: string;
  resultUnit?: string;
  referenceRange?: string;
  interpretation?: string;
  resultFlag?: 'normal' | 'low' | 'high' | 'critical' | 'abnormal';
  resultAt?: IsoDateTimeString;
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

interface TaskBase {
  id: EntityId;
  title: string;
  required: boolean;
  scheduledTime?: string; // HH:mm
  notes?: string;
}

export interface MedicineTask extends TaskBase {
  type: 'medicine';
  medicineId: EntityId;
  plannedDoseAmount?: number;
  plannedDoseUnit?: string;
}

export interface ProcedureTask extends TaskBase {
  type: 'procedure';
  procedureId: EntityId;
}

export interface RapidInsulinTask extends TaskBase {
  type: 'insulin_rapid';
  insulinProfileId: EntityId;
  plannedUnits?: number;
}

export interface BasalInsulinTask extends TaskBase {
  type: 'insulin_basal';
  insulinProfileId: EntityId;
  plannedUnits?: number;
}

export type Task = MedicineTask | ProcedureTask | RapidInsulinTask | BasalInsulinTask;

export type TaskStatus =
  | 'pending'
  | 'completed'
  | 'skipped'
  | 'failed'
  | 'missed'
  | 'late';

interface TaskResultBase {
  taskId: EntityId;
  status: TaskStatus;
  completedAt?: IsoDateTimeString;
  note?: string;
}

export interface MedicineTaskResult extends TaskResultBase {
  type: 'medicine';
  actualDoseAmount?: number;
  actualDoseUnit?: string;
}

export interface ProcedureTaskResult extends TaskResultBase {
  type: 'procedure';
}

export interface RapidInsulinTaskResult extends TaskResultBase {
  type: 'insulin_rapid';
  deliveredUnits?: number;
  glucoseMgDl?: number;
  mealTag?: string;
  baseUnits?: number;
  slidingUnits?: number;
  totalUnits?: number;
}

export interface BasalInsulinTaskResult extends TaskResultBase {
  type: 'insulin_basal';
  deliveredUnits?: number;
}

export type TaskResult =
  | MedicineTaskResult
  | ProcedureTaskResult
  | RapidInsulinTaskResult
  | BasalInsulinTaskResult;

export type IssueSeverity = 'low' | 'medium' | 'high' | 'warning' | 'critical';
export type IssueStatus = 'open' | 'in_review' | 'resolved' | 'dismissed';

export interface Issue {
  id: EntityId;
  patientId: EntityId;
  checklistDateId?: DateId;
  source: 'task' | 'ai_qa' | 'manual';
  severity: IssueSeverity;
  status: IssueStatus;
  title: string;
  description: string;
  taskId?: EntityId;
  createdAt: IsoDateTimeString;
  resolvedAt?: IsoDateTimeString;
}

export interface DailyChecklist {
  id: EntityId;
  patientId: EntityId;
  dateId: DateId;
  tasks: Task[];
  results: TaskResult[];
  issues: Issue[];
  createdAt: IsoDateTimeString;
  updatedAt: IsoDateTimeString;
}

export interface AiQaLog {
  id: EntityId;
  patientId: EntityId;
  checklistDateId?: DateId;
  issueId?: EntityId;
  model: string;
  prompt: string;
  response: string;
  flagged: boolean;
  confidence?: number;
  createdAt: IsoDateTimeString;
}
