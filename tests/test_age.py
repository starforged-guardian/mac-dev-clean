from datetime import timedelta
import unittest

from mac_dev_clean.age import parse_age


class AgeTests(unittest.TestCase):
    def test_parse_age_days_and_weeks(self):
        self.assertEqual(parse_age("60d"), timedelta(days=60))
        self.assertEqual(parse_age("2w"), timedelta(weeks=2))

    def test_parse_age_rejects_invalid_values(self):
        with self.assertRaises(ValueError):
            parse_age("yesterday")
        with self.assertRaises(ValueError):
            parse_age("0d")


if __name__ == "__main__":
    unittest.main()

