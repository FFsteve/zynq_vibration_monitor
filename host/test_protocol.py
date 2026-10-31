"""检查独立协议、分片恢复、日志与失败出口；不打开任何真实串口。"""
import csv
import json
from pathlib import Path
import tempfile
import unittest

from capture import CaptureLogs, main
from protocol import Sample, StreamDecoder, decode, encode


class ProtocolTests(unittest.TestCase):
    def test_known_vector_and_limits(self):
        sample = Sample(1, 1, -1, -32768)
        self.assertEqual(encode(sample).hex(), "a55a010001ffff800080")
        self.assertEqual(decode(encode(sample)), sample)
        for x in (-32768, -1, 0, 1, 32767):
            self.assertEqual(decode(encode(Sample(255, x, x, x))), Sample(255, x, x, x))
        for bad in ((256, 0, 0, 0), (0, 32768, 0, 0), (0, 0, -32769, 0)):
            with self.assertRaises(ValueError):
                Sample(*bad)

    def test_reject_bad_packet(self):
        good = encode(Sample(0, 1, 2, 3))
        for i in range(10):
            bad = bytearray(good)
            bad[i] ^= 1
            with self.assertRaises(ValueError):
                decode(bytes(bad))

    def test_every_chunk_size_and_headers(self):
        samples = [Sample(i, -i, 0x5AA5, -23206) for i in range(32)]
        raw = b"".join(map(encode, samples))
        for size in range(1, 24):
            parser = StreamDecoder()
            actual = []
            for offset in range(0, len(raw), size):
                actual += parser.feed(raw[offset:offset+size])
            self.assertEqual(actual, samples)
            self.assertEqual(parser.stats()["trailing_bytes"], 0)

    def test_corrupt_truncated_insert_delete_recovery(self):
        packet = encode(Sample(9, 0x1234, 0x5678, -25924))
        following = Sample(10, 1, -1, -32768)
        for damaged in ([packet[:n] for n in range(1, 10)] +
                        [packet[:n]+packet[n+1:] for n in range(10)] +
                        [packet[:n]+b"\x77"+packet[n:] for n in range(10)]):
            parser = StreamDecoder()
            result = parser.feed(b"garbage" + damaged + encode(following))
            self.assertIn(following, result)
            self.assertLessEqual(len(parser.buffer), 9)

    def test_sequence_wrap_gap_duplicate(self):
        parser = StreamDecoder()
        for seq in (254, 255, 0, 2, 2, 3):
            parser.feed(encode(Sample(seq, 0, 0, 0)))
        self.assertEqual(parser.seq_discontinuities, 2)
        self.assertEqual(parser.duplicates, 1)
        self.assertEqual(parser.gap_mod256_total, 1)

    def test_binary_csv_json_and_overwrite_guard(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            logs = CaptureLogs(p)
            raw = encode(Sample(1, 1, -1, -32768))
            logs.feed(raw[:3], 0)
            logs.feed(raw[3:], 0)
            stats = logs.close()
            self.assertEqual((p/"capture.bin").read_bytes(), raw)
            self.assertEqual(stats["frames"], 1)
            with (p/"samples.csv").open(newline="", encoding="utf-8") as f:
                row = list(csv.DictReader(f))[0]
            self.assertEqual(int(row["z"]), -32768)
            self.assertEqual(json.loads((p/"stats.json").read_text())["bytes"], 10)
            with self.assertRaises(FileExistsError):
                CaptureLogs(p)

    def test_ack_and_cli_failure(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            raw = p/"ack.bin"
            raw.write_bytes(b"\x06\x06\x07")
            self.assertEqual(main(["--input-bin", str(raw), "--mode", "ack", "--output", str(p/"bad")]), 1)
            raw.write_bytes(b"\x06\x06")
            self.assertEqual(main(["--input-bin", str(raw), "--mode", "ack", "--expect-count", "2", "--output", str(p/"good")]), 0)
            self.assertEqual(main(["--input-bin", str(raw), "--mode", "ack", "--expect-count", "3", "--output", str(p/"count_bad")]), 1)


if __name__ == "__main__":
    unittest.main()
