"""离线生成上板激励，或由操作者显式指定COM口回放；本模块导入时不打开串口。"""
import argparse,csv,hashlib,json,math,time
from pathlib import Path
from protocol import Sample,encode,decode,StreamDecoder
from stage4_reference import coefficients,dc_fixed,fir_fixed
from stage5_reference import feature_block,AlarmReference


def generate(output):
    output.mkdir(parents=True,exist_ok=True);coeff=coefficients()[1];summary=[]
    cases={'fixed':[(1,-1,-32768)]*1024}
    for freq in [5,10,20,30,50,60,80,100]:
        cases[f'tone_{freq}hz']=[(round(9000*math.sin(2*math.pi*freq*i/250)),0,0) for i in range(2500)]
    cases['alarm_cycle']=[(round((9000 if 256<=i<1024 else 0)*math.sin(2*math.pi*10*i/250)),0,0) for i in range(1600)]
    for name,axes in cases.items():
        folder=output/name;folder.mkdir(parents=True,exist_ok=True)
        filtered=list(zip(*[fir_fixed(dc_fixed([r[a] for r in axes]),coeff)[0] for a in range(3)]))
        raw=b''.join(encode(Sample(i%256,*r)) for i,r in enumerate(axes))
        wire=b''.join(encode(Sample(i%256,*(v//4 for v in r))) for i,r in enumerate(filtered))
        (folder/'input.bin').write_bytes(raw);(folder/'expected_raw.bin').write_bytes(raw);(folder/'expected_filtered.bin').write_bytes(wire)
        alarm=AlarmReference();features=[]
        for start in range(62,len(axes)-127,128):
            values=feature_block(filtered[start:start+128]);state=alarm.feed(values['mean_square'])
            features.append([len(features),start%256,(start+127)%256,*values['mean_square'],*values['rms'],*values['peak'],sum(int(v)<<a for a,v in enumerate(state['axes']))])
        with (folder/'expected_features.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.writer(f);writer.writerow(['window_id','seq_start','seq_end','ms_x','ms_y','ms_z','rms_x','rms_y','rms_z','peak_x','peak_y','peak_z','alarm_axes']);writer.writerows(features)
        info=dict(name=name,source='SYNTHETIC',sample_rate_hz=250,samples=len(axes),complete_windows=len(features),
                  input_sha256=hashlib.sha256(raw).hexdigest(),filtered_restore_scale=4,
                  reset_required=True,limitations=['必须先重新配置FPGA，不能拼接前一次基线/窗口','PC调度不保证线缆精确250Hz，须用DL16测时序','不是传感器标定'])
        (folder/'fixture.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');summary.append(info)
    (output/'fixtures.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'PASS board fixtures cases={len(summary)} output={output}')


def drive(transport,packets,period=0.004,clock=time.monotonic,sleep=time.sleep,on_read=None):
    """按实际发送起点安排下一包，延迟时不突发补发；始终正确处理短写。"""
    received=bytearray();timestamps=[];deadline=clock()
    def receive():
        chunk=transport.read(4096)
        if chunk:
            received.extend(chunk)
            if on_read:on_read(chunk)
    for packet in packets:
        while clock()<deadline:
            receive();sleep(min(0.001,max(0,deadline-clock())))
        stamp=clock();timestamps.append(stamp);offset=0
        while offset<len(packet):
            count=transport.write(packet[offset:])
            if not isinstance(count,int) or count<=0 or count>len(packet)-offset:raise IOError('串口短写无法继续，停止测试')
            offset+=count
        receive();deadline=stamp+period
    deadline=clock()+0.05
    while clock()<deadline:receive();sleep(0.001)
    receive()
    return bytes(received),timestamps


def replay(fixture,mode,port,output):
    info=json.loads((fixture/'fixture.json').read_text(encoding='utf-8'));data=(fixture/'input.bin').read_bytes()
    if hashlib.sha256(data).hexdigest()!=info['input_sha256']:raise ValueError('激励哈希错误')
    if len(data)!=info['samples']*10:raise ValueError('激励长度错误')
    packets=[data[i:i+10] for i in range(0,len(data),10)]
    for packet in packets:decode(packet)
    expected=(fixture/f'expected_{mode}.bin').read_bytes()
    # 创建独占输出，已有记录时在打开任何硬件之前拒绝。
    output.mkdir(parents=True,exist_ok=False)
    raw_file=(output/'capture.bin').open('xb')
    try:
        import serial
        with serial.Serial(port,115200,timeout=0,write_timeout=1,xonxoff=False,rtscts=False,dsrdtr=False) as link:
            link.reset_input_buffer()
            actual,stamps=drive(link,packets,1/info['sample_rate_hz'],on_read=lambda chunk:(raw_file.write(chunk),raw_file.flush()))
    except Exception as error:
        (output/'error.txt').write_text(str(error)+'\n',encoding='utf-8');raise
    finally:raw_file.close()
    decoder=StreamDecoder();samples=decoder.feed(actual);intervals=[b-a for a,b in zip(stamps,stamps[1:])]
    with (output/'samples.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.writer(f);writer.writerow(['sample_index','seq','x_wire','y_wire','z_wire']);writer.writerows((i,s.seq,s.x,s.y,s.z) for i,s in enumerate(samples))
    result=dict(status='PASS_DIGITAL_CONTENT' if actual==expected else 'FAIL_DIGITAL_CONTENT',fixture=info,
                source_mode=mode,port=port,decoder=decoder.stats(),sent_packets=len(packets),
                host_send_interval_min_s=min(intervals) if intervals else None,host_send_interval_max_s=max(intervals) if intervals else None,
                physical_timing_pass=None,sensor_calibration_pass=None,
                limitations=['只比对数字内容，实际线缆周期由逻辑分析仪验收','模式由操作者确认，包内无模式位','本测试绕过STM32和MPU6050'])
    (output/'replay_result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return 0 if actual==expected else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);commands=parser.add_subparsers(dest='command',required=True)
    gen=commands.add_parser('generate');gen.add_argument('--output',type=Path,required=True)
    run=commands.add_parser('replay');run.add_argument('--fixture',type=Path,required=True);run.add_argument('--source-mode',choices=['raw','filtered'],required=True)
    run.add_argument('--port',required=True);run.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.command=='generate':generate(args.output)
    else:raise SystemExit(replay(args.fixture,args.source_mode,args.port,args.output))
