import json
import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.domain import clean_name, overlooked_index, pair_stays


class DomainTests(unittest.TestCase):
    def test_clean_name_strips_star_and_alias(self):
        self.assertEqual(clean_name("*AZZI"), "Azzi")
        self.assertEqual(clean_name("Bubbles (freya)"), "Bubbles")
        self.assertEqual(clean_name("581"), "")
        self.assertEqual(clean_name(""), "")

    def test_coat_does_not_affect_index(self):
        self.assertEqual(overlooked_index(40, True, True, "adult"), 90)

    def test_repeat_visitor_pairs_to_next_outcome_only(self):
        intakes = [
            {
                "animal_id": "A",
                "type": "Dog",
                "source_date": "2025-01-01T10:00:00.000",
                "name_at_intake": "",
                "primary_breed": "Pit Bull",
                "primary_color": "Black",
                "date_of_birth": "2020-01-01T00:00:00.000",
                "sex": "Male",
                "source_name": "Stray",
                "found_address": "Austin",
            },
            {
                "animal_id": "A",
                "type": "Dog",
                "source_date": "2025-02-01T10:00:00.000",
                "name_at_intake": "Rex",
                "primary_breed": "Pit Bull",
                "primary_color": "Black",
                "date_of_birth": "2020-01-01T00:00:00.000",
                "sex": "Male",
                "source_name": "Owner Surrender",
                "found_address": "Austin",
            },
        ]
        outcomes = [
            {
                "animal_id": "A",
                "type": "Dog",
                "outcome_date": "2025-01-10T12:00:00.000",
                "outcome_status": "Adopted",
                "name": "Rex",
                "primary_breed": "Pit Bull",
                "primary_color": "Black",
            }
        ]
        stays = pair_stays(intakes, outcomes, as_of=date(2025, 3, 3))
        self.assertEqual(len(stays), 2)
        first = next(s for s in stays if s["intake_date"] == "2025-01-01")
        second = next(s for s in stays if s["intake_date"] == "2025-02-01")
        self.assertFalse(first["open"])
        self.assertEqual(first["days_in_care"], 9)
        self.assertEqual(first["outcome_status"], "Adopted")
        self.assertTrue(second["open"])
        self.assertEqual(second["days_in_care"], 30)
        self.assertEqual(second["stay_id"], "A-2025-02-01")

    def test_black_coat_finding_fixture_is_zero(self):
        findings = json.loads(
            Path(__file__).resolve().parents[1].joinpath("out/findings.json").read_text()
        )
        black = next(s for s in findings["splits"] if s["label"] == "All-black coat")
        self.assertEqual(black["delta"], 0.0)
        self.assertEqual(black["p"], 1.0)


if __name__ == "__main__":
    unittest.main()
