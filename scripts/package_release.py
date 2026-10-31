"""冻结本地候选交付：验证实际结果、生成HEX、保存哈希和无厂商库/PDF的自有源码包。"""
import argparse,hashlib,json,re,shutil,subprocess,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def check_hex(path):
    upper=0;size=0;eof=False
    for line in path.read_text(encoding='ascii').splitlines():
        if not line:continue
        if eof or not line.startswith(':'):raise ValueError('HEX记录顺序错误')
        record=bytes.fromhex(line[1:]);n=record[0]
        if len(record)!=n+5 or sum(record)%256:raise ValueError('HEX校验错误')
        address=int.from_bytes(record[1:3],'big');kind=record[3];data=record[4:4+n]
        if kind==4:upper=int.from_bytes(data,'big')<<16
        elif kind==0:
            start=upper+address
            if not 0x08000000<=start<start+n<=0x08010000:raise ValueError('HEX超出F103C8的64KB Flash范围')
            size+=n
        elif kind==1:eof=True
    if not eof or size==0:raise ValueError('HEX无有效程序或缺EOF')
    return size


def package(version,fromelf):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*',version):raise ValueError('版本只允许ASCII字母数字、点、横线和下划线')
    output=ROOT/'build/release'/version
    if (output/'release_manifest.json').exists():raise FileExistsError('该版本已经冻结，请选择新版本，不能覆盖交付证据')
    regression=json.loads((ROOT/'build/stage7_regression/regression_result.json').read_text(encoding='utf-8-sig'))
    if regression['status']!='PASS_STAGE7_REGRESSION' or regression['simulator']!='both':raise ValueError('必须先完成本次双工具全部回归')
    if len(regression['steps'])!=10 or any(s['exit_code'] for s in regression['steps']):raise ValueError('回归步骤不完整')
    for required in ['docs/board_test_plan.md','docs/stage7_delivery.md','report/stage7_validation.md','report/requirements_audit.md']:
        if not (ROOT/required).is_file():raise FileNotFoundError(required)
    output.mkdir(parents=True,exist_ok=True);payload={};hex_sizes={}
    def copy(source,target):
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target);assert digest(source)==digest(target)
        payload[target.relative_to(output).as_posix()]=digest(target)
    for variant in ['raw','filtered','debug']:
        folder=ROOT/'build/stage7_release'/variant
        result=(folder/'release_result.txt').read_text().strip()
        if not result.startswith('PASS stage7_release variant='+variant+' '):raise ValueError('发布构建未通过:'+variant)
        for name in ['system.bit','routed_system.dcp','utilization.rpt','timing_summary.rpt','drc.rpt','cdc.rpt','rx_sync_timing.rpt','hierarchy_check.txt']:
            copy(folder/name,output/'fpga'/variant/name)
        if variant=='debug':
            for name in ['system.ltx','probe_map.tsv']:copy(folder/name,output/'fpga'/variant/name)
    for target in ['FixedSource','SensorSource']:
        folder=ROOT/'build/stm32'/target;log=(folder/'keil_build.log').read_text(errors='replace')
        if '0 Error(s), 0 Warning(s)' not in log:raise ValueError('Keil未通过:'+target)
        dest=output/'stm32'/target;dest.mkdir(parents=True,exist_ok=True)
        copy(folder/'vibration_monitor.axf',dest/'vibration_monitor.axf');copy(folder/'keil_build.log',dest/'keil_build.log')
        hex_file=dest/'vibration_monitor.hex'
        subprocess.run([str(fromelf),'--i32combined','--output',str(hex_file),str(dest/'vibration_monitor.axf')],check=True)
        hex_sizes[target]=check_hex(hex_file);payload[hex_file.relative_to(output).as_posix()]=digest(hex_file)
    for source in (ROOT/'build/stage7_board_vectors').rglob('*'):
        if source.is_file():copy(source,output/'board_vectors'/source.relative_to(ROOT/'build/stage7_board_vectors'))
    for source in (ROOT/'build/stage7_regression').glob('*.log'):copy(source,output/'validation'/source.name)
    copy(ROOT/'build/stage7_regression/regression_result.json',output/'validation/regression_result.json')
    copy(ROOT/'report/evidence/stage6/samples_comparison.csv',output/'validation/rtl_samples_comparison.csv')
    # 只打包自有源码；库、原始PDF、自动生成IP、缓存、历史采集原文件均不随源码包分发。
    folders=['rtl','constr','sim','host','scripts','skill','data/reference/stage4','docs','report','stm32/app','stm32/bsp','stm32/config','stm32/keil']
    extensions={'.v','.vh','.xdc','.do','.tcl','.ps1','.py','.c','.h','.uvprojx','.md','.json','.yaml','.txt','.csv','.mem'}
    files={ROOT/'AGENTS.md',ROOT/'README.md',ROOT/'.gitignore',ROOT/'.gitattributes'}
    for folder in folders:
        for source in (ROOT/folder).rglob('*'):
            rel=source.relative_to(ROOT).as_posix()
            if source.is_file() and source.suffix in extensions and '__pycache__' not in source.parts and not rel.startswith('report/evidence/') and rel not in ['report/release_manifest.json','report/source_manifest.json']:
                files.add(source)
    source_hashes={source.relative_to(ROOT).as_posix():digest(source) for source in sorted(files) if source.is_file()}
    source_manifest=dict(version=version,status='FROZEN_SOFTWARE_CANDIDATE',physical_validation='PENDING',files=source_hashes,
                         exclusions=['用户STM32 Libraries需本地已有，不随自有源码分发','厂商硬件PDF及IP生成源码未收录','未制作QSPI/SD启动镜像，JTAG配置掉电不保留'])
    text=json.dumps(source_manifest,ensure_ascii=False,indent=2)+'\n'
    (output/'source_manifest.json').write_text(text,encoding='utf-8');(ROOT/'report/source_manifest.json').write_text(text,encoding='utf-8')
    archive=output/'source.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for name in source_hashes:z.write(ROOT/name,name)
        z.writestr('source_manifest.json',text)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise ValueError('源码压缩包CRC错误')
        if any('/Libraries/' in n or n.endswith('.pdf') for n in z.namelist()):raise ValueError('源码包含排除的第三方资料')
        for name,expected in source_hashes.items():assert hashlib.sha256(z.read(name)).hexdigest()==expected
    payload['source.zip']=digest(archive);payload['source_manifest.json']=digest(output/'source_manifest.json')
    result=dict(version=version,status='FROZEN_SOFTWARE_CANDIDATE',hardware_tested=False,output=str(output),source_files=len(source_hashes),
                source_manifest_sha256=digest(output/'source_manifest.json'),stm32_hex_data_bytes=hex_sizes,payload_sha256=payload,
                limitations=['新增完整功能尚未上板，按board_test_plan逐项填写','量值校准与真实采样仍待验证','ILA调试版与普通版资源不同','不保证未知竞赛正式评分条款合规'])
    text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    (output/'release_manifest.json').write_text(text,encoding='utf-8');(ROOT/'report/release_manifest.json').write_text(text,encoding='utf-8')
    for name,expected in payload.items():assert digest(output/name)==expected
    print('PASS release package version='+version+' source_files='+str(len(source_hashes))+' payload_files='+str(len(payload))+' output='+str(output))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--version',default='v1.0-rc1')
    parser.add_argument('--fromelf',type=Path,default=Path('D:/Keil_v5/Main_Program/ARM/ARMCC/bin/fromelf.exe'))
    args=parser.parse_args();package(args.version,args.fromelf)
