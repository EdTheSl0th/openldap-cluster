# GNU General Public License v3.0+ (see LICENSE or https://www.gnu.org/licenses/gpl-3.0.txt)
from __future__ import annotations

import pytest

from ansible.errors import AnsibleFilterError
from ansible_collections.openldap.cluster.plugins.filter.ldap import (
    derive_password,
    host_hostgroups,
    host_password,
    rbac_expand,
    suffix_from_domain,
)

SEED = "s" * 40


def test_derive_password_is_deterministic_and_purpose_bound():
    assert derive_password(SEED, "replicator") == derive_password(SEED, "replicator")
    assert derive_password(SEED, "replicator") != derive_password(SEED, "vrrp")
    assert derive_password(SEED, "x") != derive_password("t" * 40, "x")
    assert len(derive_password(SEED, "x")) == 40
    assert len(derive_password(SEED, "x", 8)) == 8


def test_derive_password_rejects_short_seed():
    with pytest.raises(AnsibleFilterError):
        derive_password("short", "x")


def test_host_password_unique_and_case_insensitive():
    assert host_password("a.example.org", SEED) == host_password("A.Example.ORG", SEED)
    assert host_password("a.example.org", SEED) != host_password("b.example.org", SEED)


def test_suffix_from_domain():
    assert suffix_from_domain("test.internal") == "dc=test,dc=internal"


GROUPS = [{"name": "dev", "gid": 1}, {"name": "ops", "gid": 2}]
HOSTGROUPS = [
    {"name": "all", "gid": 10, "hosts": ["ALL"]},
    {"name": "web", "gid": 11, "hosts": ["web1.example.org"]},
]
ROLES = [
    {
        "name": "admin",
        "groups": ["ops", "dev"],
        "host_access": ["all"],
        "sudo": [{"hostgroups": ["all"], "commands": ["ALL"]}],
    },
    {
        "name": "developer",
        "groups": ["dev"],
        "host_access": ["web"],
        "sudo": [{"hostgroups": ["web"], "commands": ["/bin/true"], "options": ["!authenticate"]}],
    },
]


def test_rbac_expand_resolves_roles():
    users = [
        {"uid": "alice", "roles": ["admin"]},
        {"uid": "bob", "roles": ["developer"], "groups": ["ops"]},
        {"uid": "gone", "roles": ["admin"], "state": "absent"},
    ]
    res = rbac_expand(users, ROLES, GROUPS, HOSTGROUPS)
    assert res["groups"] == {"dev": ["alice", "bob"], "ops": ["alice", "bob"]}
    assert res["roles"] == {"admin": ["alice"], "developer": ["bob"]}
    assert res["access"] == {"all": ["alice"], "web": ["bob"]}
    rules = {r["name"]: r for r in res["sudo"]}
    assert rules["admin-0"]["hosts"] == ["ALL"]
    assert rules["developer-0"]["hosts"] == ["web1", "web1.example.org"]
    assert rules["developer-0"]["users"] == ["bob"]
    assert rules["developer-0"]["options"] == ["!authenticate"]


@pytest.mark.parametrize(
    "users",
    [
        [{"uid": "x", "roles": ["missing"]}],
        [{"uid": "x", "groups": ["missing"]}],
        [{"uid": "x", "host_access": ["missing"]}],
    ],
)
def test_rbac_expand_rejects_unknown_references(users):
    with pytest.raises(AnsibleFilterError):
        rbac_expand(users, ROLES, GROUPS, HOSTGROUPS)


def test_host_hostgroups():
    assert host_hostgroups(HOSTGROUPS, ["web1", "web1.example.org"]) == ["all", "web"]
    assert host_hostgroups(HOSTGROUPS, ["db1"]) == ["all"]
