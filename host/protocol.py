"""十字节协议的独立 PC 实现；原始计数不作重力去除或单位换算。"""

from dataclasses import dataclass
from functools import reduce
from operator import xor


@dataclass(frozen=True)
class Sample:
    seq: int
    x: int
    y: int
    z: int

    def __post_init__(self):
        if not 0 <= self.seq <= 255:
            raise ValueError("序号必须在 0..255")
        if any(not -32768 <= v <= 32767 for v in (self.x, self.y, self.z)):
            raise ValueError("三轴必须是 16 位带符号整数")


def encode(sample: Sample) -> bytes:
    payload = bytes([sample.seq]) + b"".join(
        value.to_bytes(2, "big", signed=True) for value in (sample.x, sample.y, sample.z)
    )
    return b"\xa5\x5a" + payload + bytes([reduce(xor, payload, 0)])


def decode(packet: bytes) -> Sample:
    if len(packet) != 10 or packet[:2] != b"\xa5\x5a":
        raise ValueError("长度或包头错误")
    if reduce(xor, packet[2:], 0) != 0:
        raise ValueError("XOR 校验错误")
    return Sample(packet[2], *(int.from_bytes(packet[i:i+2], "big", signed=True) for i in (3, 5, 7)))


class StreamDecoder:
    """逐字节搜索，缓存最多九个未提交字节；不以操作系统分块时间冒充硬件超时。"""

    def __init__(self):
        self.buffer = bytearray()
        self.frames = 0
        self.checksum_errors = 0
        self.discarded_bytes = 0
        self.seq_discontinuities = 0
        self.duplicates = 0
        self.gap_mod256_total = 0
        self.last_seq = None

    def feed(self, chunk: bytes):
        samples = []
        for value in chunk:
            self.buffer.append(value)
            if len(self.buffer) < 10:
                continue
            if self.buffer[:2] == b"\xa5\x5a":
                try:
                    sample = decode(bytes(self.buffer))
                except ValueError:
                    self.checksum_errors += 1
                else:
                    if self.last_seq is not None and sample.seq != (self.last_seq + 1) % 256:
                        self.seq_discontinuities += 1
                        if sample.seq == self.last_seq:
                            self.duplicates += 1
                        else:
                            self.gap_mod256_total += (sample.seq - self.last_seq - 1) % 256
                    self.last_seq = sample.seq
                    self.frames += 1
                    samples.append(sample)
                    self.buffer.clear()
                    continue
            del self.buffer[0]
            self.discarded_bytes += 1
        return samples

    def stats(self):
        return {
            "frames": self.frames,
            "checksum_errors": self.checksum_errors,
            "discarded_bytes": self.discarded_bytes,
            "trailing_bytes": len(self.buffer),
            "seq_discontinuities": self.seq_discontinuities,
            "duplicates": self.duplicates,
            "gap_mod256_total": self.gap_mod256_total,
        }
