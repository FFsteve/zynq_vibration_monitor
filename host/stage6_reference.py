"""第六阶段设计参考：验证18转16位尺度、回包和带宽，不运行RTL或硬件。"""
import json
from pathlib import Path
from protocol import Sample,encode,decode

ROOT=Path(__file__).resolve().parents[1]


def filtered_wire(value):
    if not isinstance(value,int) or not -131072<=value<=131071:
        raise ValueError('滤波输入必须为signed18整数')
    return value//4


def validate_mode(mode):
    if mode not in (0,1):
        raise ValueError('回传模式只允许0或1')


def generate():
    out=ROOT/'build/stage6_reference'
    out.mkdir(parents=True,exist_ok=True)
    maximum_error=0
    with (out/'selector_vectors.txt').open('w',encoding='ascii',newline='\n') as f:
        for i,value in enumerate(range(-131072,131072)):
            axes=[value,-1-value,((value*37+131072)&262143)-131072]
            wire=[filtered_wire(x) for x in axes]
            for x,y in zip(axes,wire):
                error=x-4*y
                assert -32768<=y<=32767 and 0<=error<=3
                maximum_error=max(maximum_error,error)
            sample=Sample(i%256,*wire)
            assert decode(encode(sample))==sample
            assert len(encode(sample))==10
            f.write(' '.join(str(x) for x in axes+wire)+'\n')
    rejected=0
    for mode in [-1,2]:
        try:validate_mode(mode)
        except ValueError:rejected+=1
    for value in [-131073,131072,1.5]:
        try:filtered_wire(value)
        except ValueError:rejected+=1
    assert rejected==5
    for axes in [(1,-1,-32768),(32767,-32768,0),(-23206,23205,17)]:
        sample=Sample(255,*axes)
        assert decode(encode(sample))==sample
    baud=115200;sample_rate=250;clk_hz=50000000
    bit_clks=(clk_hz+baud//2)//baud
    summary=dict(status='PASS_STAGE6_NUMERIC_DESIGN_ONLY',mode_approval='APPROVED_2026_10_31',
                 selector_vectors=262144,wire_roundtrips=262144,axis_coverage_each=262144,
                 maximum_restore_error_counts=maximum_error,invalid_cases_rejected=rejected,
                 output_bytes=10,filtered_shift=2,filtered_restore_scale=4,
                 nominal_samples_per_second=sample_rate,nominal_bits_per_second=sample_rate*100,
                 nominal_uart_occupancy=sample_rate*100/baud,bit_clks=bit_clks,
                 minimum_packet_wire_clks=bit_clks*100,
                 compressed_clk_hz=1152000,compressed_baud=baud,compressed_bit_clks=10,
                 compressed_sample_clks=4608,compressed_byte_timeout=2304,compressed_gap=13824,
                 limitations=['本脚本只验证数值，RTL结果见独立实现记录',
                              '本数值参考不执行ModelSim/XSim、完整实现或板测',
                              '包内无模式字段，采集必须提供模式元数据'])
    (out/'design_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS stage6 numerical design '+json.dumps({k:summary[k] for k in ['selector_vectors','maximum_restore_error_counts','invalid_cases_rejected','nominal_uart_occupancy']}))
    print('RTL_NOT_RUN_BY_THIS_SCRIPT')


if __name__=='__main__':generate()
