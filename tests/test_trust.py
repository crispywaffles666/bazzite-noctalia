import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TrustBootstrap(unittest.TestCase):
    def test_preserves_other_rules_and_is_idempotent(self):
        original = {"default": [{"type": "reject"}], "transports": {
            "docker": {"example.com/keep": [{"type": "reject"}]},
            "containers-storage": {"": [{"type": "insecureAcceptAnything"}]}}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy = root / "etc/containers/policy.json"
            policy.parent.mkdir(parents=True)
            policy.write_text(json.dumps(original))
            for _ in range(2):
                subprocess.run(["bash", str(ROOT / "scripts/install-image-trust.sh"), str(root)], check=True,
                               capture_output=True)
            result = json.loads(policy.read_text())
            rule = result["transports"]["docker"].pop("ghcr.io/crispywaffles666/bazzite-noctalia")
            self.assertEqual(result, original)
            self.assertEqual(rule[0]["type"], "sigstoreSigned")
            self.assertEqual(json.loads(policy.with_suffix(".json.before-bazzite-noctalia").read_text()), original)
            self.assertEqual((root / rule[0]["keyPath"].lstrip("/")).read_bytes(), (ROOT / "cosign.pub").read_bytes())

    def test_invalid_policy_fails_before_installing_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy = root / "etc/containers/policy.json"
            policy.parent.mkdir(parents=True)
            policy.write_text("not JSON")
            result = subprocess.run(["bash", str(ROOT / "scripts/install-image-trust.sh"), str(root)],
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(policy.read_text(), "not JSON")
            self.assertFalse((root / "etc/pki").exists())


if __name__ == "__main__":
    unittest.main()
