.PHONY: new-project update-project archive-project

new-project:
	@bash scripts/project-manager.sh new

update-project:
	@bash scripts/project-manager.sh update

archive-project:
	@bash scripts/project-manager.sh archive
