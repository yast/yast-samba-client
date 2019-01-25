from yast import Declare, ycpbuiltins, import_module
import_module('PackageSystem')
import_module('Package')
from yast import PackageSystem, Package

# Check if a given workgroup is a Active Directory domain and return the name
# of AD domain controler
#
# @param workgroup      the name of a workgroup to be tested
# @return string        non empty when ADS was found
@Declare('string', 'string')
def GetLDAPDS(workgroup):
    if not PackageSystem.Installed('samba-python3'):
        if not Package.InstallAll(['samba-python3']):
            return ''
    from samba.net import Net
    from samba.credentials import Credentials
    from samba.dcerpc import nbt
    net = Net(Credentials())
    cldap_ret = net.finddc(domain=workgroup, flags=(nbt.NBT_SERVER_LDAP | nbt.NBT_SERVER_DS))
    ycpbuiltins.y2milestone('Found LDAP/DS server %s via cldap ping' % cldap_ret.pdc_dns_name)
    return cldap_ret.pdc_dns_name

