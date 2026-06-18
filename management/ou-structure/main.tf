# Read the Organizations root ID.
data "aws_organizations_organization" "current" {}

# ── Parent OUs (under Root) ────────────────────────────────────────────────

resource "aws_organizations_organizational_unit" "chain_vote_ai" {
  name      = "chain-vote-ai"
  parent_id = data.aws_organizations_organization.current.roots[0].id

  tags = {
    ManagedBy = "opentofu"
    Phase     = "01-foundation"
  }
}

resource "aws_organizations_organizational_unit" "chain_vote_voting" {
  name      = "chain-vote-voting"
  parent_id = data.aws_organizations_organization.current.roots[0].id

  tags = {
    ManagedBy = "opentofu"
    Phase     = "01-foundation"
  }
}

# ── Child OUs under chain-vote-ai ─────────────────────────────────────────
# parent_id references the parent OU resource attribute — OpenTofu's dependency
# graph ensures chain_vote_ai is created before any resource that references it.
# No explicit depends_on needed; the attribute reference IS the dependency.

resource "aws_organizations_organizational_unit" "chain_vote_ai_dev" {
  name      = "dev"
  parent_id = aws_organizations_organizational_unit.chain_vote_ai.id

  tags = {
    ManagedBy   = "opentofu"
    Phase       = "01-foundation"
    Environment = "dev"
    Workload    = "chain-vote-ai"
  }
}

resource "aws_organizations_organizational_unit" "chain_vote_ai_staging" {
  name      = "staging"
  parent_id = aws_organizations_organizational_unit.chain_vote_ai.id

  tags = {
    ManagedBy   = "opentofu"
    Phase       = "01-foundation"
    Environment = "staging"
    Workload    = "chain-vote-ai"
  }
}

resource "aws_organizations_organizational_unit" "chain_vote_ai_prod" {
  name      = "prod"
  parent_id = aws_organizations_organizational_unit.chain_vote_ai.id

  tags = {
    ManagedBy   = "opentofu"
    Phase       = "01-foundation"
    Environment = "prod"
    Workload    = "chain-vote-ai"
  }
}

# ── Child OUs under chain-vote-voting ─────────────────────────────────────

resource "aws_organizations_organizational_unit" "chain_vote_voting_dev" {
  name      = "dev"
  parent_id = aws_organizations_organizational_unit.chain_vote_voting.id

  tags = {
    ManagedBy   = "opentofu"
    Phase       = "01-foundation"
    Environment = "dev"
    Workload    = "chain-vote-voting"
  }
}

resource "aws_organizations_organizational_unit" "chain_vote_voting_staging" {
  name      = "staging"
  parent_id = aws_organizations_organizational_unit.chain_vote_voting.id

  tags = {
    ManagedBy   = "opentofu"
    Phase       = "01-foundation"
    Environment = "staging"
    Workload    = "chain-vote-voting"
  }
}

resource "aws_organizations_organizational_unit" "chain_vote_voting_prod" {
  name      = "prod"
  parent_id = aws_organizations_organizational_unit.chain_vote_voting.id

  tags = {
    ManagedBy   = "opentofu"
    Phase       = "01-foundation"
    Environment = "prod"
    Workload    = "chain-vote-voting"
  }
}
