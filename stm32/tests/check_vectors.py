"""用独立的 PC 解码器检查 C 固件实际生成的数据。"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "host"))
from protocol import StreamDecoder, Sample

decoder = StreamDecoder()
samples = decoder.feed(Path(sys.argv[1]).read_bytes())
expected = [Sample(i, i - 16, 32767 - i, -32768 + i) for i in range(32)]
if samples != expected or decoder.checksum_errors or decoder.buffer:
    raise SystemExit("FAIL firmware_vectors")
print("PASS firmware_vectors samples=32 errors=0")
