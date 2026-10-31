"""回放器的确定性离线检查；所有传输均使用假设备，不打开真实COM口。"""
import tempfile,unittest
from pathlib import Path
from board_test import drive,replay
from protocol import Sample,encode


class FakeClock:
    def __init__(self):self.now=0
    def clock(self):return self.now
    def sleep(self,delay):self.now+=delay


class FakeSerial:
    def __init__(self,clock,chunk=10,blocking=0):self.clock=clock;self.chunk=chunk;self.blocking=blocking;self.sent=bytearray();self.pending=bytearray()
    def write(self,data):
        n=min(self.chunk,len(data));self.sent.extend(data[:n]);self.pending.extend(data[:n]);self.clock.now+=self.blocking;return n
    def read(self,n):
        data=bytes(self.pending[:n]);del self.pending[:n];return data


class BoardToolsTests(unittest.TestCase):
    def test_partial_writes_and_receive(self):
        clock=FakeClock();link=FakeSerial(clock,3);packets=[encode(Sample(i,1,-1,-32768)) for i in range(10)]
        actual,stamps=drive(link,packets,clock=clock.clock,sleep=clock.sleep)
        self.assertEqual(actual,b''.join(packets));self.assertEqual(bytes(link.sent),actual)
        self.assertTrue(all(abs(b-a-.004)<1e-9 for a,b in zip(stamps,stamps[1:])))

    def test_late_writes_never_burst_catchup(self):
        clock=FakeClock();link=FakeSerial(clock,blocking=.010)
        _,stamps=drive(link,[encode(Sample(i,0,0,0)) for i in range(5)],clock=clock.clock,sleep=clock.sleep)
        self.assertTrue(all(b-a>=.009999 for a,b in zip(stamps,stamps[1:])))

    def test_zero_write_stops(self):
        clock=FakeClock();link=FakeSerial(clock,0)
        with self.assertRaises(IOError):drive(link,[encode(Sample(0,0,0,0))],clock=clock.clock,sleep=clock.sleep)

    def test_capture_directory_protected_before_hardware(self):
        import hashlib,json
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp);fixture=folder/'fixture';fixture.mkdir();output=folder/'existing';output.mkdir()
            packet=encode(Sample(0,1,2,3));(fixture/'input.bin').write_bytes(packet);(fixture/'expected_raw.bin').write_bytes(packet)
            (fixture/'fixture.json').write_text(json.dumps(dict(samples=1,input_sha256=hashlib.sha256(packet).hexdigest())),encoding='utf-8')
            with self.assertRaises(FileExistsError):replay(fixture,'raw','NOT_A_REAL_PORT',output)


if __name__=='__main__':unittest.main()
