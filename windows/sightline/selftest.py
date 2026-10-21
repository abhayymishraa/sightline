"""Gaze checks, the same as the macOS `swift run selfcheck`. Run: python -m unittest sightline.selftest"""
import json
import random
import unittest

from .gaze import (GazeRegressor, HeadAngle, HeadPose, LookSample, MissCounter, OneEuroFilter,
                            ScreenPicker, ScreenProfile)


class FilterTests(unittest.TestCase):
    def test_filter(self):
        f = OneEuroFilter(0.25, 0.03)
        self.assertEqual(f(10, 0), 10)
        first = f(20, 1 / 15)
        self.assertTrue(10 < first < 20)
        for i in range(2, 301):
            last = f(20, i / 15)
        self.assertLess(abs(last - 20), 0.01)


class RegressorTests(unittest.TestCase):
    def test_maps_held_out_point(self):
        inputs, outputs = [], []
        for x in (0.1, 0.3, 0.5, 0.7, 0.9):
            for y in (0.1, 0.5, 0.9):
                inputs.append(HeadPose(30 * (x - 0.5), 15 * (y - 0.5), 0.4).features(0.4, False))
                outputs.append((x, y))
        model = GazeRegressor.train(inputs, outputs)
        self.assertIsNotNone(model)
        gx, gy = model.map(HeadPose(30 * 0.1, 15 * -0.2, 0.4).features(0.4, False))
        self.assertLess(abs(gx - 0.6), 0.05)
        self.assertLess(abs(gy - 0.3), 0.05)

    def test_far_face_scales_up(self):
        self.assertTrue(10 < HeadPose(10, 0, 0.2).scaled(0.4).yaw < 20)


class PickerTests(unittest.TestCase):
    def test_switching(self):
        anchors = {"L": [HeadAngle(25, 0), HeadAngle(15, 0)], "R": [HeadAngle(-15, 0), HeadAngle(-25, 0)]}
        p = ScreenPicker()

        def step(yaw, t):
            return p.step(HeadAngle(yaw, 0), anchors, delay=0.2, boundary=0.5, now=t)

        step(20, 0)
        self.assertEqual(p.screen, "L")
        self.assertIsNone(step(5, 0.1)); self.assertIsNone(step(5, 0.5))
        self.assertIsNone(step(-10, 1.0))
        self.assertEqual(step(-10, 1.3), "R")
        self.assertIsNone(step(-2, 2.0)); self.assertIsNone(step(-2, 2.5))
        step(12, 3.0)
        self.assertEqual(step(12, 3.3), "L")
        self.assertIsNone(step(80, 4.0))
        self.assertEqual(p.screen, "L")

    def test_miss_counter(self):
        m = MissCounter()
        flagged = any([m.note("L", True) for _ in range(8)])
        self.assertTrue(flagged and m.is_unreliable("L"))


class ProfileTests(unittest.TestCase):
    def make(self):
        rnd = random.Random(7)
        samples = []
        for x, y in ((0.5, 0.5), (0.97, 0.25), (0.97, 0.5), (0.97, 0.75)):
            for _ in range(12):
                n = rnd.uniform(-0.3, 0.3)
                samples.append(LookSample(HeadPose(20 * (x - 0.5) + n, 10 * (y - 0.5) + n, 0.35,
                                                   pupil_x=0.3 * (x - 0.5), pupil_y=0.3 * (y - 0.5)), x, y))
        for x, y in ((0.15, 0.5), (0.85, 0.5), (0.5, 0.15), (0.5, 0.85)):
            for _ in range(12):
                samples.append(LookSample(HeadPose(0, 0, 0.35, pupil_x=0.3 * (x - 0.5), pupil_y=0.3 * (y - 0.5)),
                                          x, y, eyes_only_phase=True))
        return ScreenProfile.build([HeadAngle(0, 0), HeadAngle(9.4, 0)], samples)

    def test_pupils_help_and_locate(self):
        p = self.make()
        self.assertTrue(p.pupils_useful)
        x, _ = p.locate(HeadPose(0, 0, 0.35, pupil_x=0.3 * (0.2 - 0.5), pupil_y=0))
        self.assertLess(abs(x - 0.2), 0.1)

    def test_round_trip_and_clicks(self):
        p = self.make()
        q = ScreenProfile.from_json(json.loads(json.dumps(p.to_json())))
        self.assertEqual(q.anchors, p.anchors)
        self.assertEqual(q.pupils_useful, p.pupils_useful)
        for _ in range(10):
            p.absorb_click(HeadPose(3, 0, 0.35, face_mid_x=0.6, pupil_x=0, pupil_y=0), (0.5, 0.5))
        self.assertGreater(p.seat_shift(HeadPose(0, 0, 0.35, face_mid_x=0.6)).yaw, 1.5)


if __name__ == "__main__":
    unittest.main()
