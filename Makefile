# MoliShot — 常用命令
#
#   make build        开发构建（Debug）
#   make test         跑单元测试
#   make dmg          打 Release 包（dist/MoliShot.dmg）
#   make tag V=0.7.5  打 tag 并推送，触发 CI 自动发 GitHub Release
#   make clean        清理 build 产物
#
# 版本号唯一来源：project.yml 的 MARKETING_VERSION（打 tag 前先改它并提交）。

APP        := MoliShot
SCHEME     := MoliShot
PROJECT    := MoliShot.xcodeproj
BUILD_DIR  := build
DEFAULT_GOAL := help

.PHONY: help gen build test dmg package tag clean

help: ## 打印本帮助
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## / — /'

gen: ## xcodegen 重新生成 Xcode 工程
	xcodegen generate

build: gen ## Debug 构建（开发联调）
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

test: gen ## 跑全量单元测试
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' test

dmg: ## 打 Release DMG（dist/MoliShot.dmg）
	./scripts/build-dmg.sh

package: dmg ## dmg 的别名

tag: ## 打 tag 并推送以触发 Release，用法：make tag V=0.7.5
ifndef V
	$(error 用法：make tag V=0.7.5)
endif
	@git diff --quiet && git diff --cached --quiet || (echo "工作区不干净，先提交再打 tag" >&2; exit 1)
	@grep -q 'MARKETING_VERSION: "$(V)"' project.yml || (echo "project.yml 里 MARKETING_VERSION 不是 $(V)，先改版本号并提交" >&2; exit 1)
	@git rev-parse "v$(V)" >/dev/null 2>&1 && (echo "tag v$(V) 已存在" >&2; exit 1) || true
	git tag -a "v$(V)" -m "release v$(V)"
	git push origin "v$(V)"

clean: ## 清理 build 目录
	rm -rf $(BUILD_DIR)
