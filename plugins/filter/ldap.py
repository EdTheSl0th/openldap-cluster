# -*- coding: utf-8 -*-
# GNU General Public License v3.0+ (see https://www.gnu.org/licenses/gpl-3.0.txt)
"""Filters for openldap.cluster: deterministic secrets and RBAC expansion."""

from __future__ import annotations

import base64
import hashlib
import hmac

from ansible.errors import AnsibleFilterError


def derive_password(seed, purpose, length=40):
    """Derive a stable secret from a master seed and a purpose string.

    HMAC-SHA256(seed, purpose), base64url without padding. Same inputs always
    yield the same password, different purposes never collide, and nothing
    needs to be stored besides the seed.
    """
    if not seed or len(str(seed)) < 32:
        raise AnsibleFilterError("derive_password: seed must be at least 32 characters")
    digest = hmac.new(str(seed).encode(), str(purpose).encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip("=")[: int(length)]


def host_password(fqdn, seed):
    """Bind password of a client host account (unique per FQDN)."""
    return derive_password(seed, "host:" + str(fqdn).lower())


def suffix_from_domain(domain):
    return ",".join("dc=" + part for part in str(domain).split(".") if part)


def _index(items, kind, key="name"):
    out = {}
    for item in items or []:
        if key not in item:
            raise AnsibleFilterError("%s entry without '%s': %r" % (kind, key, item))
        out[item[key]] = item
    return out


def rbac_expand(users, roles, groups, hostgroups):
    """Resolve users -> roles -> groups / host access / sudo rules.

    Returns a dict with, per object, the list of member uids:
      groups:     {group: [uid, ...]}        posix groups (direct + via roles)
      roles:      {role: [uid, ...]}         role objects in ou=roles
      access:     {hostgroup: [uid, ...]}    login permission per hostgroup
      sudo:       [{name, users, hosts, commands, runas, options, order}]
    Users with state=absent are ignored. Unknown references fail loudly.
    """
    roles_by_name = _index(roles, "role")
    groups_by_name = _index(groups, "group")
    hg_by_name = _index(hostgroups, "hostgroup")

    res_groups = {g: [] for g in groups_by_name}
    res_roles = {r: [] for r in roles_by_name}
    res_access = {h: [] for h in hg_by_name}

    def check(name, table, kind, where):
        if name not in table:
            raise AnsibleFilterError("%s references unknown %s '%s'" % (where, kind, name))

    for user in users or []:
        if user.get("state", "present") == "absent":
            continue
        uid = user["uid"]
        eff_groups = set(user.get("groups", []))
        eff_access = set(user.get("host_access", []))
        for role in user.get("roles", []):
            check(role, roles_by_name, "role", "user " + uid)
            res_roles[role].append(uid)
            eff_groups.update(roles_by_name[role].get("groups", []))
            eff_access.update(roles_by_name[role].get("host_access", []))
        for g in sorted(eff_groups):
            check(g, groups_by_name, "group", "user " + uid)
            res_groups[g].append(uid)
        for h in sorted(eff_access):
            check(h, hg_by_name, "hostgroup", "user " + uid)
            res_access[h].append(uid)

    sudo = []
    for rname in sorted(roles_by_name):
        role = roles_by_name[rname]
        for idx, rule in enumerate(role.get("sudo", [])):
            hosts = []
            for hg in rule.get("hostgroups", []):
                check(hg, hg_by_name, "hostgroup", "sudo rule of role " + rname)
                for h in hg_by_name[hg].get("hosts", []):
                    hosts.append(h)
                    if h != "ALL" and "." in h:
                        hosts.append(h.split(".")[0])
            sudo.append({
                "name": "%s-%d" % (rname, idx),
                "role": rname,
                "users": sorted(res_roles[rname]),
                "hosts": sorted(set(hosts)) or ["ALL"],
                "commands": rule.get("commands", ["ALL"]),
                "runas": rule.get("runas", ["ALL"]),
                "options": rule.get("options", []),
                "order": rule.get("order", 10),
            })

    return {
        "groups": {k: sorted(v) for k, v in res_groups.items()},
        "roles": {k: sorted(v) for k, v in res_roles.items()},
        "access": {k: sorted(v) for k, v in res_access.items()},
        "sudo": sudo,
    }


def host_hostgroups(hostgroups, names):
    """Hostgroups a host belongs to; names = [inventory_hostname, fqdn, ...]."""
    names = {str(n).lower() for n in names}
    out = []
    for hg in hostgroups or []:
        members = {str(h).lower() for h in hg.get("hosts", [])}
        if "all" in members or names & members:
            out.append(hg["name"])
    return out


class FilterModule:
    def filters(self):
        return {
            "derive_password": derive_password,
            "host_password": host_password,
            "suffix_from_domain": suffix_from_domain,
            "rbac_expand": rbac_expand,
            "host_hostgroups": host_hostgroups,
        }
