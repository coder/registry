import { describe, expect, it } from "bun:test";
import {
	runTerraformApply,
	runTerraformInit,
	testRequiredVariables,
} from "~test";

describe("aws-ami-snapshot", async () => {
	await runTerraformInit(import.meta.dir);

	testRequiredVariables(import.meta.dir, {
		instance_id: "i-1234567890abcdef0",
		default_ami_id: "ami-12345678",
		template_name: "test-template",
	});

	it("supports optional variables", async () => {
		await testRequiredVariables(import.meta.dir, {
			instance_id: "i-1234567890abcdef0",
			default_ami_id: "ami-12345678",
			template_name: "test-template",
			enable_dlm_cleanup: true,
			dlm_role_arn: "arn:aws:iam::123456789012:role/dlm-lifecycle-role",
			snapshot_retention_count: 5,
			tags: {
				Environment: "test",
				Project: "coder",
			},
		});
	});
});