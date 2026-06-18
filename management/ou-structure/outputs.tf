# Parent OU outputs
output "chain_vote_ai_ou_id" {
  description = "OU ID for chain-vote-ai (parent). Used as CT registration target and AFT account request parent_ou."
  value       = aws_organizations_organizational_unit.chain_vote_ai.id
}

output "chain_vote_voting_ou_id" {
  description = "OU ID for chain-vote-voting (parent). Used as CT registration target and AFT account request parent_ou."
  value       = aws_organizations_organizational_unit.chain_vote_voting.id
}

# Child OU outputs — chain-vote-ai
output "chain_vote_ai_dev_ou_id" {
  description = "OU ID for chain-vote-ai/dev."
  value       = aws_organizations_organizational_unit.chain_vote_ai_dev.id
}

output "chain_vote_ai_staging_ou_id" {
  description = "OU ID for chain-vote-ai/staging."
  value       = aws_organizations_organizational_unit.chain_vote_ai_staging.id
}

output "chain_vote_ai_prod_ou_id" {
  description = "OU ID for chain-vote-ai/prod."
  value       = aws_organizations_organizational_unit.chain_vote_ai_prod.id
}

# Child OU outputs — chain-vote-voting
output "chain_vote_voting_dev_ou_id" {
  description = "OU ID for chain-vote-voting/dev."
  value       = aws_organizations_organizational_unit.chain_vote_voting_dev.id
}

output "chain_vote_voting_staging_ou_id" {
  description = "OU ID for chain-vote-voting/staging."
  value       = aws_organizations_organizational_unit.chain_vote_voting_staging.id
}

output "chain_vote_voting_prod_ou_id" {
  description = "OU ID for chain-vote-voting/prod."
  value       = aws_organizations_organizational_unit.chain_vote_voting_prod.id
}

output "organizations_root_id" {
  description = "Root ID of the AWS Organization. Used by CT registration and AFT."
  value       = data.aws_organizations_organization.current.roots[0].id
}
