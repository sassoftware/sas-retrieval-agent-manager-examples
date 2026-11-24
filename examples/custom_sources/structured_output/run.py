# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

import ast
import csv
import json
import os
from datetime import date, datetime
from enum import Enum
from typing import TypeVar

from pydantic import BaseModel, Field


class BloodType(str, Enum):
    A_pos = "A+"
    A_neg = "A-"
    B_pos = "B+"
    B_neg = "B-"
    AB_pos = "AB+"
    AB_neg = "AB-"
    O_pos = "O+"
    O_neg = "O-"
    unknown = "unknown"


class PatientRecord(BaseModel):
    """
    Persistent patient profile. One record per patient.
    Used for demographic filtering and patient-level retrieval.
    """

    patient_id: str = Field(..., description="Unique patient identifier, e.g. P-00123")
    first_name: str
    last_name: str
    date_of_birth: date
    age: int
    blood_type: BloodType
    phone: str | None = None
    email: str | None = None


class VisitType(str, Enum):
    routine = "routine"
    follow_up = "follow_up"
    emergency = "emergency"
    specialist = "specialist"
    telehealth = "telehealth"


class ClinicalEncounter(BaseModel):
    """
    A single patient visit. Links to PatientRecord via patient_id.
    The `notes` field is the primary surface for semantic search.
    """

    encounter_id: str = Field(..., description="Unique encounter ID, e.g. E-00456")
    patient_id: str = Field(..., description="Foreign key → PatientRecord.patient_id")
    visit_date: date
    visit_type: VisitType
    attending_physician: str

    chief_complaint: str = Field(..., description="Reason for visit in plain language")

    # Diagnosis
    primary_diagnosis: str = Field(..., description="Human-readable diagnosis")
    icd10_code: str = Field(..., description="ICD-10 code, e.g. E11.9")
    secondary_diagnoses: list[str] = Field(default_factory=list)

    # Free-text clinical note — rich surface for semantic retrieval
    notes: str = Field(..., description="Physician narrative notes from the encounter")

    follow_up_required: bool = False
    follow_up_reason: str | None = None
    follow_up_days: int | None = Field(
        None, description="Recommended days until follow-up"
    )


class LabStatus(str, Enum):
    normal = "normal"
    abnormal_low = "abnormal_low"
    abnormal_high = "abnormal_high"
    critical = "critical"


class LabResult(BaseModel):
    """
    A lab order containing one or more test panels.
    Links to PatientRecord and optionally to ClinicalEncounter.
    """

    lab_id: str = Field(..., description="Unique lab result ID, e.g. L-00321")
    patient_id: str
    encounter_id: str | None = None
    ordering_physician: str

    panel_name: str = Field(
        ..., description="e.g. Comprehensive Metabolic Panel, CBC, Lipid Panel"
    )
    collected_at: datetime
    resulted_at: datetime | None = None
    lab_facility: str | None = None

    # Rolled-up interpretation
    overall_status: LabStatus = LabStatus.normal
    interpretation: str | None = Field(
        None,
        description="Physician interpretation or automated summary of findings",
    )


class MedicationStatus(str, Enum):
    active = "active"
    discontinued = "discontinued"
    on_hold = "on_hold"
    completed = "completed"


class Medication(BaseModel):
    """
    A single prescription record.
    """

    medication_id: str = Field(..., description="Unique ID, e.g. M-00789")
    patient_id: str
    encounter_id: str | None = Field(None, description="Encounter where prescribed")

    name: str = Field(..., description="Generic or brand name, e.g. Metformin")
    brand_name: str | None = None
    drug_class: str = Field(..., description="e.g. Biguanide, ACE Inhibitor, SSRI")
    indication: str = Field(..., description="What condition this treats")

    dose: str = Field(..., description="e.g. 500mg")
    frequency: str = Field(..., description="e.g. twice daily, every 8 hours")
    route: str = Field(..., description="oral, IV, topical, inhaled, etc.")
    start_date: date
    end_date: date | None = None

    prescribing_physician: str
    status: MedicationStatus = MedicationStatus.active
    notes: str | None = Field(None, description="Special instructions or rationale")


class GeneratedData(BaseModel):
    patient_records: list[PatientRecord] = Field(
        default_factory=list, description="Patient profiles."
    )
    medications: list[Medication] = Field(
        default_factory=list, description="Patient medications."
    )
    lab_results: list[LabResult] = Field(
        default_factory=list, description="Patient lab results."
    )
    clinical_encounters: list[ClinicalEncounter] = Field(
        default_factory=list, description="Patient visits."
    )


GENERATED_DATA_SCHEMA = GeneratedData.model_json_schema()

NUM_GENERATED_PATIENTS = int(os.getenv("NUM_GENERATED_PATIENTS", "10"))

GENERATION_PROMPT = f"""
Generate synthetic medical records for {NUM_GENERATED_PATIENTS} patients.
Include medications, lab results, and clinical encounters.
"""


def exec(client):
    print("Generating data with the following schema:")
    print(json.dumps(GENERATED_DATA_SCHEMA, indent=4))
    invocation = client.invoke_llm(
        content=GENERATION_PROMPT,
        structured_output_schema=GENERATED_DATA_SCHEMA,
    )

    output_content_str: str = invocation.response
    output_content_dict: dict = ast.literal_eval(output_content_str)

    structured_output: GeneratedData = GeneratedData.model_validate(output_content_dict)
    print(f"Generated {len(structured_output.patient_records)} patient records.")
    print(f"Generated {len(structured_output.medications)} medications.")
    print(f"Generated {len(structured_output.lab_results)} lab results.")
    print(
        f"Generated {len(structured_output.clinical_encounters)} clinical encounters."
    )

    write_csv(
        client,
        filepath="/tmp/patients.csv",
        model=PatientRecord,
        data=structured_output.patient_records,
    )
    write_csv(
        client,
        filepath="/tmp/medications.csv",
        model=Medication,
        data=structured_output.medications,
    )
    write_csv(
        client,
        filepath="/tmp/lab_results.csv",
        model=LabResult,
        data=structured_output.lab_results,
    )
    write_csv(
        client,
        filepath="/tmp/clinical_encounters.csv",
        model=ClinicalEncounter,
        data=structured_output.clinical_encounters,
    )


T = TypeVar("T", bound=BaseModel)


def write_csv(client, filepath: str, model: T, data: list[T]):
    """
    This method takes a list of data and writes it out as a csv file.

    Assumptions:
        - The model MUST be "flat":
            - No nested Pydantic models
            - No lists, dicts, or other container types
            - No complex/custom types
        - All fields must be representable as simple scalar values (str, int, float, bool, etc.)
        - Field order is determined by `model.model_fields`
        - `model_dump()` values are written directly and cast to strings
    """
    column_headers = list(model.model_fields.keys())
    with open(filepath, "w") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(column_headers)

        for item in data:
            row: list[str] = []
            for value in item.model_dump().values():
                row.append(str(value))
            writer.writerow(row)
    client.save_file(filepath)
