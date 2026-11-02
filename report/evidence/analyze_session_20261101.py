"""离线核查20秒初始化记录；按复位分段，不修改原始采集或工程。"""

import bisect
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import sys
import zipfile
from collections import Counter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from host.protocol import decode, StreamDecoder

BASE = ROOT / 'report/evidence/20261101_session01'
OUT = ROOT / 'report/evidence/20261101_session01_analysis'


def time_s(text):
    value, unit = text.split()
    return float(value) * {'s': 1, 'ms': 1e-3, 'us': 1e-6,
                          'μs': 1e-6, 'µs': 1e-6, 'ns': 1e-9}[unit]


def rows(name):
    with (BASE / name).open(encoding='gb18030', newline='') as stream:
        reader = csv.reader(stream)
        next(reader)
        for row in reader:
            if len(row) >= 5:
                yield {'index': int(row[0]), 'time': time_s(row[1]),
                       'duration': time_s(row[2]), 'kind': row[3], 'value': row[4]}


def uart(name):
    words, warnings, byte_issues = [], [], []
    start, bits, word = None, [], None
    last_row = None
    for row in rows(name):
        last_row = row
        kind, value = row['kind'], row['value']
        if kind == 'TX data' and value == 'Start bit':
            if word is not None:
                byte_issues.append({'time': word['time'], 'issue': '前一字节缺少停止位'})
            start, bits, word = row, [], None
        elif kind == 'TX bits':
            bits.append(row)
        elif kind == 'TX data' and re.fullmatch('[0-9A-Fa-f]{2}', value):
            word = dict(row, byte=int(value, 16), start=start['time'] if start else None)
            valid_bits = (len(bits) == 8 and all(b['value'] in ('0', '1') for b in bits))
            word['bits_ok'] = valid_bits and sum(int(b['value']) << i for i, b in enumerate(bits)) == word['byte']
            # CSV在秒级采用有限小数位；容许两个时间标签舍入造成的约1微秒差。
            word['start_ok'] = start is not None and abs(row['time'] - start['time'] - start['duration']) < 1.1e-6
            word['stop_ok'] = False
            words.append(word)
        elif kind == 'TX data' and value == 'Stop bit':
            if word is not None:
                word['stop_ok'] = abs(row['time'] - word['time'] - word['duration']) < 1.1e-6
                word['end'] = row['time'] + row['duration']
                if not all(word[k] for k in ('bits_ok', 'start_ok', 'stop_ok')):
                    byte_issues.append({'time': word['time'], 'issue': '位值或起止位不一致'})
            else:
                byte_issues.append({'time': row['time'], 'issue': '停止位缺少字节记录'})
            word = None
        else:
            warnings.append(row)
    frames, skipped, bad_checksums = [], [], []
    offset = 0
    while offset < len(words):
        block = words[offset:offset + 10]
        if len(block) == 10 and [w['byte'] for w in block[:2]] == [0xA5, 0x5A]:
            packet = bytes(w['byte'] for w in block)
            try:
                sample = decode(packet)
            except ValueError:
                bad_checksums.append({'time': block[0]['time'], 'hex': packet.hex(' ')})
            else:
                if (all(w['bits_ok'] and w['start_ok'] and w['stop_ok'] for w in block)
                        and all(b['start'] - a['end'] < 0.002 for a, b in zip(block, block[1:]))):
                    frames.append({'time': block[0]['start'], 'end': block[-1]['end'],
                                   'seq': sample.seq, 'axes': [sample.x, sample.y, sample.z],
                                   'hex': packet.hex(' ').upper(), 'payload': packet[3:9].hex().upper()})
                    offset += 10
                    continue
        skipped.append({'time': words[offset]['time'], 'byte': words[offset]['byte']})
        offset += 1
    oracle = StreamDecoder()
    independent = oracle.feed(bytes(w['byte'] for w in words))
    assert [(s.seq, [s.x, s.y, s.z]) for s in independent] == [(f['seq'], f['axes']) for f in frames]
    gaps = [{'before': a['time'], 'after': b['time'], 'seconds': b['time'] - a['time'],
             'previous_seq': a['seq'], 'next_seq': b['seq']}
            for a, b in zip(frames, frames[1:]) if b['time'] - a['time'] > 0.012]
    groups = [[]]
    for f in frames:
        if groups[-1] and f['time'] - groups[-1][-1]['time'] > 0.012:
            groups.append([])
        groups[-1].append(f)
    return {'frames': frames, 'groups': groups, 'gaps': gaps,
            'bytes': len(words), 'byte_issues': byte_issues, 'warnings': warnings,
            'bad_checksums': bad_checksums, 'skipped': skipped, 'oracle': oracle.stats(),
            'last_annotation_end': last_row['time'] + last_row['duration'],
            'trailing_incomplete_bits': len(bits) if word is not None or (start and start['time'] > frames[-1]['end']) else 0}


def i2c(name='init_i2c.csv'):
    transactions, detail, problems, partial = [], [], [], []
    for row in rows(name):
        if row['kind'] == 'Address/data':
            detail.append(row)
        elif row['kind'] == 'Packets':
            text = row['value']
            match = re.fullmatch(r'0x68 WR: ([0-9A-F]{2}) \[SR\] 0x68 RD: ([0-9A-F ]+)', text)
            write = re.fullmatch(r'0x68 WR: ([0-9A-F]{2}) ([0-9A-F]{2})', text)
            if match:
                register = match[1]
                data = bytes.fromhex(match[2])
                expected = ['Address write: 68', 'Write', 'ACK', f'Data write: {register}',
                            'ACK', 'Address read: 68', 'Read', 'ACK']
                for n, value in enumerate(data):
                    expected += [f'Data read: {value:02X}', 'NACK' if n == len(data) - 1 else 'ACK']
                mode = 'read'
            elif write:
                register = write[1]
                data = bytes.fromhex(write[2])
                expected = ['Address write: 68', 'Write', 'ACK', f'Data write: {register}',
                            'ACK', f'Data write: {write[2]}', 'ACK']
                mode = 'write'
            else:
                partial.append(row)
                detail = []
                continue
            values = [d['value'] for d in detail]
            if values != expected:
                problems.append({'packet': row, 'detail': values, 'expected': expected})
            transactions.append({'time': row['time'], 'end': row['time'] + row['duration'],
                                 'mode': mode, 'register': register, 'data': data.hex().upper(),
                                 'ack_ok': values == expected})
            detail = []
        elif row['kind'] != 'Bits':
            problems.append({'annotation': row})
    return {'transactions': transactions, 'problems': problems, 'partial_packets': partial,
            'trailing_detail': detail}


def summary(frames):
    intervals = [(b['time'] - a['time']) * 1000 for a, b in zip(frames, frames[1:])]
    axes = list(zip(*(f['axes'] for f in frames)))
    half = len(frames) // 2
    seq_errors = [{'time': b['time'], 'previous': a['seq'], 'next': b['seq']}
                  for a, b in zip(frames, frames[1:]) if b['seq'] != (a['seq'] + 1) % 256]
    outliers = [{'time': b['time'], 'interval_ms': dt, 'previous_seq': a['seq'], 'seq': b['seq']}
                for a, b, dt in zip(frames, frames[1:], intervals) if not 3.9 <= dt <= 4.1]
    return {'count': len(frames), 'first_s': frames[0]['time'], 'last_s': frames[-1]['time'],
            'sample_span_s': frames[-1]['time'] - frames[0]['time'],
            'first_seq': frames[0]['seq'], 'last_seq': frames[-1]['seq'],
            'mean': [statistics.mean(a) for a in axes], 'std': [statistics.stdev(a) for a in axes],
            'min': [min(a) for a in axes], 'max': [max(a) for a in axes],
            'half_mean_difference': [statistics.mean(a[half:]) - statistics.mean(a[:half]) for a in axes],
            'mean_norm_g_at_16384': statistics.mean(math.sqrt(sum(v*v for v in f['axes'])) / 16384 for f in frames),
            'interval_mean_ms': statistics.mean(intervals), 'interval_min_ms': min(intervals),
            'interval_max_ms': max(intervals), 'rate_over_span_hz': (len(frames) - 1) / (frames[-1]['time'] - frames[0]['time']),
            'sequence_errors': seq_errors, 'wraps': sum(a['seq'] == 255 and b['seq'] == 0 for a, b in zip(frames, frames[1:])),
            'interval_outliers': outliers,
            'saturated_samples': sum(any(v in (-32768, 32767) for v in f['axes']) for f in frames)}


def main():
    OUT.mkdir(exist_ok=True)
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in BASE.iterdir() if p.is_file()}
    with zipfile.ZipFile(BASE / 'init_raw.atkdl') as z:
        assert z.testzip() is None
        config = dict(line.split('=', 1) for line in z.read('set.ini').decode('utf-8-sig').splitlines() if '=' in line)
        settings = json.loads(config['settingData'])
        enabled = [c['id'] for c in json.loads(config['channelsSet']) if c['enable']]
    d0, d1, bus = uart('init_d0_uart.csv'), uart('init_d1_uart.csv'), i2c()
    replies = d1['frames'];reply_times = [f['time'] for f in replies]
    bursts = [t for t in bus['transactions'] if t['mode'] == 'read' and t['register'] == '3B']
    burst_ends = [t['end'] for t in bursts]
    chain_failures, delays, matched_reply_indices = [], [], set()
    for f in d0['frames']:
        i = bisect.bisect_right(burst_ends, f['time']) - 1
        sensor_ok = i >= 0 and 0 <= f['time'] - bursts[i]['end'] < 100e-6 and f['payload'] == bursts[i]['data']
        j = bisect.bisect_left(reply_times, f['time'])
        candidates = [k for k in range(j, min(j + 3, len(replies)))
                      if 0 <= replies[k]['time'] - f['time'] < 0.003 and replies[k]['hex'] == f['hex']]
        if not sensor_ok or len(candidates) != 1:
            chain_failures.append({'frame': f, 'i2c_ok': sensor_ok, 'reply_candidates': candidates})
        else:
            k = candidates[0];assert k not in matched_reply_indices;matched_reply_indices.add(k)
            delays.append((replies[k]['time'] - f['time']) * 1e6)
    expected = {'75': '68', '6B': '01', '1A': '02', '19': '03', '1C': '00', '38': '01'}
    init = [t for t in bus['transactions'] if t['register'] not in ('3A', '3B')]
    readback = {r: [t for t in init if t['mode'] == 'read' and t['register'] == r] for r in expected}
    init_ok = all(len(readback[r]) == 1 and readback[r][0]['data'] == v and readback[r][0]['ack_ok'] for r, v in expected.items())
    segments = [summary(g) for g in d0['groups']]
    steady = summary([f for f in d0['groups'][-1] if f['time'] >= d0['groups'][-1][0]['time'] + 1])
    result = {'scope': '20秒已有记录的离线核查，用户确认原SensorSource、固定静止且Z正方向朝上，中途复位一次',
              'original_sha256': hashes, 'archive_crc_ok': True, 'archive_settings': settings,
              'enabled_channels': enabled, 'initialization_readback_pass': init_ok,
              'initialization_transactions': init, 'i2c_transaction_count': len(bus['transactions']),
              'i2c_register_counts': dict(Counter(t['register'] for t in bus['transactions'])),
              'i2c_problems': bus['problems'], 'i2c_boundary_packets': bus['partial_packets'],
              'd0': {k: v for k, v in d0.items() if k not in ('frames', 'groups')},
              'd1': {k: v for k, v in d1.items() if k not in ('frames', 'groups')},
              'd0_segments': segments, 'post_restart_excluding_first_second': steady,
              'chain_compared': len(delays), 'chain_failures': chain_failures,
              'unmatched_d1_frames': [f for i, f in enumerate(replies) if i not in matched_reply_indices],
              'i2c_accel_bursts': len(bursts),
              'reply_delay_us': {'mean': statistics.mean(delays), 'min': min(delays), 'max': max(delays)},
              'formal_calibration_pass': False, 'physical_configuration_or_firmware_changed': False}
    with (OUT / 'frames.csv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream);writer.writerow(['segment', 'time_s', 'seq', 'x', 'y', 'z'])
        for n, group in enumerate(d0['groups']):
            for f in group:writer.writerow([n, f['time'], f['seq'], *f['axes']])
    (OUT / 'analysis.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    assert all(hashlib.sha256((BASE / name).read_bytes()).hexdigest() == digest for name, digest in hashes.items())
    print(json.dumps({k: result[k] for k in ('initialization_readback_pass', 'i2c_transaction_count',
          'i2c_register_counts', 'chain_compared', 'chain_failures', 'unmatched_d1_frames', 'reply_delay_us')}, ensure_ascii=False))
    for n, s in enumerate(segments):
        print('SEGMENT', n, json.dumps({**s, 'interval_outliers': {'count': len(s['interval_outliers']), 'first': s['interval_outliers'][:6]}}, ensure_ascii=False))
    print('UART_COUNTS', len(d0['frames']), len(d1['frames']), 'GAPS', d0['gaps'],
          'ISSUES',len(d0['byte_issues']),len(d1['byte_issues']),len(bus['problems']),
          'WARNINGS',len(d0['warnings']),len(d1['warnings']),
          'SKIPPED',d0['skipped'],d1['skipped'])
    print('PASS session_analysis originals_unchanged formal_calibration_pass=false')


if __name__ == '__main__':
    main()
