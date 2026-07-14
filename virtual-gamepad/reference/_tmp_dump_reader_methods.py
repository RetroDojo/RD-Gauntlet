from zipfile import ZipFile
from androguard.core.dex import DEX
jar=r"C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet\_tmp_uinput.jar"
d=DEX(ZipFile(jar).read('classes.dex'))
reader=[c for c in d.get_classes() if c.get_name()=='Lcom/android/commands/uinput/Event$Reader;'][0]
out=[]
for m in reader.get_methods():
    if m.get_name() in ('readInt','readBus','setCommand','getNextEvent'):
        out.append(f"\n=== {m.get_name()} {m.get_descriptor()} ===")
        for ins in m.get_code().get_bc().get_instructions():
            out.append(f"{ins.get_name():24} {ins.get_output()}")
open(r"C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet\_tmp_reader_more.txt","w",encoding='utf-8').write('\n'.join(out))
print('wrote')
