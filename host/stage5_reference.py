"""第五阶段设计参考：窗口能量、整数RMS、峰值与滞回报警；不操作RTL或硬件。"""

import argparse
import json
import math
import random
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def validate(log2=7,on=2000,off=1500,assert_windows=2,release_windows=2):
    if not 0<=log2<=10:
        raise ValueError('窗口对数必须在0到10')
    if not 0<=off<on<=131072:
        raise ValueError('阈值必须满足0<=OFF<ON<=131072')
    if not 1<=assert_windows<=255 or not 1<=release_windows<=255:
        raise ValueError('连续窗口数必须在1到255')


def sqrt_digit(value):
    """设计中的逐二位开方算法；正确性由独立math.isqrt核查。"""
    if not 0<=value<(1<<36):
        raise ValueError('被开方数必须为36位无符号值')
    root=0
    remainder=0
    for shift in range(34,-1,-2):
        remainder=(remainder<<2)|((value>>shift)&3)
        trial=(root<<2)|1
        if remainder>=trial:
            remainder-=trial
            root=(root<<1)|1
        else:
            root<<=1
    return root,remainder


def feature_block(samples):
    if not samples or len(samples)&(len(samples)-1):
        raise ValueError('需要完整的二次幂窗口')
    if any(len(row)!=3 or any(not -131072<=int(x)<=131071 for x in row) for row in samples):
        raise ValueError('输入必须为三轴signed18')
    energy=[sum(int(row[a])**2 for row in samples) for a in range(3)]
    mean=[value//len(samples) for value in energy]
    peak=[max(abs(int(row[a])) for row in samples) for a in range(3)]
    rms=[math.isqrt(value) for value in mean]
    return dict(energy=energy,mean_square=mean,peak=peak,rms=rms)


class WindowReference:
    """只在样本域收集；周期、ready和并发优先级须由后续RTL自检。"""
    def __init__(self,log2=7):
        validate(log2=log2)
        self.length=1<<log2
        self.rows=[]
        self.previous=None
        self.start=None
        self.window_id=0
        self.aborted=0
        self.events=[]

    def clear(self):
        if self.rows:
            self.aborted+=1
        self.rows=[]
        self.previous=None
        self.start=None

    def feed(self,seq,axes):
        if not 0<=seq<256:
            raise ValueError('序号必须为8位')
        if self.previous is not None and seq!=(self.previous+1)%256:
            self.clear()
        if not self.rows:
            self.start=seq
        self.previous=seq
        self.rows.append(tuple(axes))
        if len(self.rows)==self.length:
            result=feature_block(self.rows)
            result.update(window_id=self.window_id,seq_start=self.start,seq_end=seq)
            self.events.append(result)
            self.window_id+=1
            self.rows=[]
            return result
        return None


class AlarmReference:
    def __init__(self,on=2000,off=1500,assert_windows=2,release_windows=2):
        validate(on=on,off=off,assert_windows=assert_windows,release_windows=release_windows)
        self.on=on
        self.off=off
        self.assert_windows=assert_windows
        self.release_windows=release_windows
        self.clear()

    def clear(self):
        self.axes=[False]*3
        self.up=[0]*3
        self.down=[0]*3
        self.valid=False

    def feed(self,mean):
        if len(mean)!=3 or any(not 0<=x<=1<<34 for x in mean):
            raise ValueError('均方值越界')
        rises=[]
        falls=[]
        for a,value in enumerate(mean):
            if not self.axes[a]:
                self.up[a]=self.up[a]+1 if value>=self.on*self.on else 0
                self.down[a]=0
                if self.up[a]>=self.assert_windows:
                    self.axes[a]=True
                    self.up[a]=0
                    rises.append(a)
            else:
                self.down[a]=self.down[a]+1 if value<=self.off*self.off else 0
                self.up[a]=0
                if self.down[a]>=self.release_windows:
                    self.axes[a]=False
                    self.down[a]=0
                    falls.append(a)
        self.valid=True
        return dict(axes=list(self.axes),any=any(self.axes),valid=self.valid,rises=rises,falls=falls)


def generate(destination):
    destination.mkdir(parents=True,exist_ok=True)
    rng=random.Random(20261031)
    roots={0,1,2,3,(1<<35)-1,1<<35,(1<<36)-1}
    for value in [1,2,3,15,255,256,65535,131071,131072,262143]:
        roots.update(x for x in [value*value-1,value*value,value*value+1] if 0<=x<1<<36)
    roots.update(rng.randrange(1<<36) for _ in range(10000))
    for value in roots:
        root,remainder=sqrt_digit(value)
        assert root==math.isqrt(value)
        assert remainder==value-root*root
        assert root*root<=value<(root+1)*(root+1)
        assert 0<=remainder<1<<19
    n=128
    cases={
        'zero':[(0,0,0)]*n,
        'constant_signed':[(2000,-1500,32767)]*n,
        'fullscale_negative':[(-131072,-131072,-131072)]*n,
        'fullscale_positive':[(131071,131071,131071)]*n,
        'alternating_extremes':[(-131072,131071,-1),(131071,-131072,1)]*(n//2),
        'impulse_first':[(-131072,5000,-9000)]+[(0,0,0)]*(n-1),
        'impulse_last':[(0,0,0)]*(n-1)+[(-131072,5000,-9000)],
        'sine_integer_cycles':[(round(10000*math.sin(2*math.pi*10*i/n)),
                                round(8000*math.cos(2*math.pi*13*i/n)),
                                round(5000*math.sin(2*math.pi*17*i/n))) for i in range(n)],
        'random_fullscale':[(rng.randrange(-131072,131072),rng.randrange(-131072,131072),rng.randrange(-131072,131072)) for _ in range(n)],
    }
    case_results={}
    for name,rows in cases.items():
        model=WindowReference()
        result=None
        for i,row in enumerate(rows):
            event=model.feed((250+i)%256,row)
            if i<n-1:
                assert event is None
            else:
                result=event
        assert result is not None
        independent=feature_block(rows)
        assert all(result[k]==independent[k] for k in independent)
        assert result['seq_start']==250 and result['seq_end']==121
        assert all(x<1<<43 for x in result['energy'])
        assert all(0<=x<=1<<34 for x in result['mean_square'])
        for mse,rms in zip(result['mean_square'],result['rms']):
            assert rms*rms<=mse<(rms+1)*(rms+1)
        case_results[name]=result
    assert case_results['fullscale_negative']['peak']==[131072]*3
    assert case_results['fullscale_negative']['rms']==[131072]*3
    assert case_results['impulse_first']['mean_square']==case_results['impulse_last']['mean_square']
    assert case_results['impulse_first']['peak']==case_results['impulse_last']['peak']
    assert case_results['impulse_last']['mean_square'][0]==(1<<27)
    for log2 in [0,1,2,7,10]:
        model=WindowReference(log2)
        for i in range((1<<log2)*2):
            model.feed(i%256,(1234,-4321,0))
        assert len(model.events)==2 and all(e['rms']==[1234,4321,0] for e in model.events)
    # 丢弃部分窗口后，序号重复或跳变均从当前样本建立新窗口。
    model=WindowReference(2)
    model.feed(254,(1,2,3));model.feed(255,(1,2,3));model.feed(0,(1,2,3))
    assert model.aborted==0 and not model.events
    model.feed(4,(100,200,300))
    assert model.aborted==1
    model.feed(5,(100,200,300));model.feed(5,(400,500,600))
    assert model.aborted==2
    for seq in [6,7,8]:
        model.feed(seq,(400,500,600))
    assert model.events[-1]['rms']==[400,500,600]
    model.feed(9,(1,1,1));model.clear()
    assert not model.rows and model.aborted==3
    alarm=AlarmReference()
    trace=[]
    for values,expect in [([2000**2,0,0],False),([2000**2,0,0],True),
                          ([1750**2,0,0],True),([1500**2,0,0],True),
                          ([1750**2,0,0],True),([1500**2,0,0],True),([1500**2,0,0],False)]:
        result=alarm.feed(values)
        assert result['axes'][0]==expect
        trace.append(result)
    alarm.clear();assert not alarm.valid and not any(alarm.axes)
    alarm.feed([1999**2,2000**2,2000**2]);result=alarm.feed([1999**2,2000**2,2000**2])
    assert result['axes']==[False,True,True] and result['any']
    single=AlarmReference(on=131072,off=131071,assert_windows=1,release_windows=1)
    assert single.feed([1<<34,0,0])['axes'][0]
    assert not single.feed([131071**2,0,0])['axes'][0]
    rejected=0
    for kwargs in [dict(log2=-1),dict(log2=11),dict(on=0),dict(on=1500,off=1500),
                   dict(on=131073),dict(off=-1),dict(assert_windows=0),dict(release_windows=256)]:
        try:
            validate(**kwargs)
        except ValueError:
            rejected+=1
    assert rejected==8
    for value in [-1,1<<36]:
        try:sqrt_digit(value)
        except ValueError:rejected+=1
    assert rejected==10
    summary=dict(status='PASS_STAGE5_NUMERIC_DESIGN_ONLY',sqrt_vectors=len(roots),
                 feature_cases=case_results,alarm_trace=trace,invalid_cases_rejected=rejected,
                 window_length=128,nominal_window_ms=512,rms_on=2000,rms_off=1500,
                 assert_windows=2,release_windows=2,
                 limitations=['本数值参考不包含RTL/TB运行结果','ModelSim/XSim和综合结果见独立实现验收记录',
                              '阈值为原始计数演示参数，不是故障标准','真实采样和校准问题保留'])
    (destination/'design_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with (destination/'sqrt_vectors.txt').open('w',encoding='ascii',newline='\n') as out:
        for value in sorted(roots):
            root=math.isqrt(value)
            out.write(f'{value} {root} {value-root*root}\n')
    print(json.dumps({k:summary[k] for k in ['status','sqrt_vectors','invalid_cases_rejected','window_length','nominal_window_ms']},ensure_ascii=False,indent=2))
    print('PASS feature_cases=9 parameter_windows=5 stream_recovery alarm_hysteresis; RTL_NOT_RUN_BY_THIS_SCRIPT')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description='第五阶段窗口特征和报警的数值设计参考')
    parser.add_argument('--output-dir',type=Path,default=ROOT/'build/stage5_reference')
    generate(parser.parse_args().output_dir)
