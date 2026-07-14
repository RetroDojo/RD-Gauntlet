from zipfile import ZipFile
import sys
try:
    from androguard.core.bytecodes import dvm
except Exception as e:
    print('IMPORT_ERROR', e)
    sys.exit(2)
jar=r"C:\Users\User\OneDrive\Retro Dojo\RD-Gauntlet\_tmp_uinput.jar"
with ZipFile(jar,'r') as z:
    dex=z.read('classes.dex')
d=dvm.DalvikVMFormat(dex)
keywords=['configuration','UI_SET','abs_info','descriptor','source','events','command','duration','register','inject','Expected END_ARRAY','missing','type','data','bus','pid','vid','port','absInfo']
for s in d.get_strings():
    if any(k in s for k in keywords):
        print(s)
