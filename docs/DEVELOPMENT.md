# 开发与验证

## 重新生成安装包

```powershell
python tools/build_release.py
```

构建器读取 `package/manifest.json`，验证每个资源及增量补丁的 SHA-256，再将分发文件压缩至 `dist/`。它不读取或修改游戏目录。玩家安装时不需要 Python。

`package/Installer.ps1` 支持 `Install`、`Uninstall`、`Verify` 三种模式和 `-GamePath`、`-NonInteractive` 参数。安装只接受匹配的原版文件，或由同一安装器记录的同版本安装；不会覆盖未知补丁。

## 安装器测试

先准备未安装其他补丁的 Steam 英文版 2.1.2500：

```powershell
python tools/test_installer.py --clean-game "D:\SteamLibrary\steamapps\common\Space Rangers HD A War Apart"
```

测试只复制必要文件到临时目录，所有安装、卸载、故障注入均在临时副本中进行。原游戏目录保持不变。

本次发行已验证：16 个目标文件与当前游戏实测补丁的哈希一致；重复安装保留原备份；卸载完整还原；UTF-16 模组选项及后续选择得到保留；不匹配版本、损坏资源、损坏备份和更新后的文件安全拒绝；第二个文件写入失败时回滚第一个程序补丁；Windows PowerShell 下的 Steam 自动识别；ZIP 解压后中文及含空格目录的安装/卸载。

## 资源与修复

- `translations/zh-CN.jsonl` 是 56,396 条校对译文的参考汇总；不附带完整英文原文。少量后续界面修复以 `package/Payload` 内最终资源为准。编辑该参考汇总不会自动重建 DAT、PKG 或字体。
- `package/Payload/Mods/Tweaks/Chinese` 是最终游戏可用语言模组。包内还有字体桥接资源及官方模组显示信息。
- `package/Patches` 仅包含 Rangers.exe 和 steam_ach.dll 的差异数据。安装器在匹配的原版上应用补丁，生成后再次校验完整文件哈希。
- Rangers.exe 的补丁控制中文语言包激活时的模组显示信息；steam_ach.dll 的补丁仅替换激活时的成就名称及描述。保留原统计和解锁逻辑。
- 当前字库构建和游戏资源编译流程尚未整理成便携工具；这里的构建器重新打包已生成的资源，不声称能从译文汇总直接重新编译整个汉化。

不要将访问令牌、游戏原文件、存档、个人路径、测试备份或内部运行日志提交到仓库。
