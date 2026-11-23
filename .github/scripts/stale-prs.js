// Labels and closes pull requests that are waiting on their author.
//
// A PR is waiting on its author when the latest comment or review from someone
// other than the author is newer than the author's latest comment, review, or
// push. Bots are ignored, and an approval does not count as waiting on the
// author. PRs with no human feedback yet are never labeled.
//
// - Waiting on the author for DAYS_BEFORE_STALE days: add the stale label.
// - Still waiting DAYS_BEFORE_CLOSE days after labeling: close the PR.
// - The author comments, reviews, or pushes: remove the stale label.
//
// PRs are processed oldest first, and at most OPERATIONS_PER_RUN label or
// close actions are taken per run. Set DRY_RUN=true to only log actions.

const DAY_MS = 24 * 60 * 60 * 1000;

const isBot = (user) =>
  !user || user.type === "Bot" || user.login.endsWith("[bot]");

const toTime = (value) => (value ? Date.parse(value) : 0);

async function getActivity({ github, owner, repo, pr, staleLabel }) {
  const author = pr.user.login;
  const activity = {
    lastAuthorAt: 0,
    lastOtherAt: 0,
    lastOtherIsApproval: false,
    staleLabeledAt: 0,
  };

  const record = (user, time, isApproval = false) => {
    const at = toTime(time);
    if (!at || isBot(user)) {
      return;
    }
    if (user.login === author) {
      activity.lastAuthorAt = Math.max(activity.lastAuthorAt, at);
    } else if (at > activity.lastOtherAt) {
      activity.lastOtherAt = at;
      activity.lastOtherIsApproval = isApproval;
    }
  };

  const timeline = await github.paginate(
    github.rest.issues.listEventsForTimeline,
    { owner, repo, issue_number: pr.number, per_page: 100 },
  );
  for (const event of timeline) {
    switch (event.event) {
      case "commented":
        record(event.user ?? event.actor, event.created_at);
        break;
      case "reviewed": {
        const state = (event.state ?? "").toLowerCase();
        if (state !== "pending") {
          record(event.user, event.submitted_at, state === "approved");
        }
        break;
      }
      case "line-commented":
        for (const comment of event.comments ?? []) {
          record(comment.user, comment.created_at);
        }
        break;
      case "head_ref_force_pushed":
        if (event.actor?.login === author) {
          record(event.actor, event.created_at);
        }
        break;
      case "labeled":
        if (event.label?.name === staleLabel) {
          activity.staleLabeledAt = Math.max(
            activity.staleLabeledAt,
            toTime(event.created_at),
          );
        }
        break;
    }
  }

  // Pushes count as author activity. Merge commits from "Update branch" are
  // attributed to whoever clicked it, so they only count for the author.
  const commits = await github.paginate(github.rest.pulls.listCommits, {
    owner,
    repo,
    pull_number: pr.number,
    per_page: 100,
  });
  for (const commit of commits) {
    if (commit.author?.login === author || commit.committer?.login === author) {
      activity.lastAuthorAt = Math.max(
        activity.lastAuthorAt,
        toTime(commit.commit?.committer?.date),
      );
    }
  }

  return activity;
}

async function ensureLabel({ github, owner, repo, name, dryRun, core }) {
  try {
    await github.rest.issues.getLabel({ owner, repo, name });
  } catch (error) {
    if (error.status !== 404) {
      throw error;
    }
    const verb = dryRun ? "[dry run] Would create" : "Creating";
    core.info(`${verb} label "${name}"`);
    if (!dryRun) {
      await github.rest.issues.createLabel({
        owner,
        repo,
        name,
        color: "ededed",
        description: "Waiting on the author; closes automatically if no reply",
      });
    }
  }
}

module.exports = async ({ github, context, core }) => {
  const { owner, repo } = context.repo;
  const staleLabel = process.env.STALE_LABEL || "stale";
  const daysBeforeStale = Number(process.env.DAYS_BEFORE_STALE || 7);
  const daysBeforeClose = Number(process.env.DAYS_BEFORE_CLOSE || 3);
  const operationsPerRun = Number(process.env.OPERATIONS_PER_RUN || 60);
  const dryRun = process.env.DRY_RUN === "true";
  const now = Date.now();
  let operations = 0;

  const act = async (description, fn) => {
    operations++;
    core.info(`${dryRun ? "[dry run] Would " : ""}${description}`);
    if (!dryRun) {
      await fn();
    }
  };

  await ensureLabel({ github, owner, repo, name: staleLabel, dryRun, core });

  const prs = await github.paginate(github.rest.pulls.list, {
    owner,
    repo,
    state: "open",
    sort: "created",
    direction: "asc",
    per_page: 100,
  });
  core.info(`Checking ${prs.length} open PRs`);

  for (const pr of prs) {
    if (operations >= operationsPerRun) {
      core.info(`Reached ${operationsPerRun} operations; stopping early`);
      break;
    }

    const activity = await getActivity({ github, owner, repo, pr, staleLabel });
    const isStale = pr.labels.some((label) => label.name === staleLabel);
    const waitingOnAuthor =
      activity.lastOtherAt > activity.lastAuthorAt &&
      !activity.lastOtherIsApproval;
    const issue = { owner, repo, issue_number: pr.number };

    if (isStale) {
      // If the label event is missing, never close based on unknown timing.
      const labeledAt = activity.staleLabeledAt || now;
      if (!waitingOnAuthor || activity.lastAuthorAt > labeledAt) {
        await act(`remove "${staleLabel}" from #${pr.number}`, () =>
          github.rest.issues.removeLabel({ ...issue, name: staleLabel }),
        );
      } else if (now - labeledAt >= daysBeforeClose * DAY_MS) {
        await act(`close #${pr.number}`, () =>
          github.rest.pulls.update({
            owner,
            repo,
            pull_number: pr.number,
            state: "closed",
          }),
        );
      }
      continue;
    }

    if (
      waitingOnAuthor &&
      now - activity.lastOtherAt >= daysBeforeStale * DAY_MS
    ) {
      await act(`add "${staleLabel}" to #${pr.number}`, () =>
        github.rest.issues.addLabels({ ...issue, labels: [staleLabel] }),
      );
    }
  }

  core.info(`Done after ${operations} operations`);
};
