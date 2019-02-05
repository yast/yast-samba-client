from yast import Declare, ycpbuiltins, import_module
import_module('PackageSystem')
import_module('Package')
from yast import PackageSystem, Package

# Global response to net.finddc()
cldap_ret = None

def net_lookup(domain):
    global cldap_ret
    if not PackageSystem.Installed('samba-python3'):
        if not Package.InstallAll(['samba-python3']):
            return
    from samba.net import Net
    from samba.credentials import Credentials
    from samba.dcerpc import nbt
    net = Net(Credentials())
    cldap_ret = net.finddc(domain=domain, flags=(nbt.NBT_SERVER_LDAP | nbt.NBT_SERVER_DS))

# Check if a given workgroup is a Active Directory domain and return the name
# of AD domain controler
#
# @param workgroup      the name of a workgroup to be tested
# @return string        non empty when ADS was found
@Declare('string', 'string')
def GetLDAPDS(workgroup):
    global cldap_ret
    if not cldap_ret:
        net_lookup(workgroup)
    ycpbuiltins.y2milestone('Found LDAP/DS server %s via cldap ping' % cldap_ret.pdc_dns_name if cldap_ret else '')
    return cldap_ret.pdc_dns_name if cldap_ret else ''

# Get AD Domain name and return the name of work group ("Pre-Win2k Domain")
# @param domain the domain user entered
# @param server AD server (used for querying)
# @return       workgroup (returns domain if anything fails)
@Declare('string', 'string', 'string')
def ADDomain2Workgroup(domain, server):
    global cldap_ret
    if not cldap_ret or server != cldap_ret.pdc_dns_name:
        net_lookup(domain)
    ycpbuiltins.y2milestone('workgroup: %s' % cldap_ret.domain_name if cldap_ret else domain)
    return cldap_ret.domain_name if cldap_ret else domain
