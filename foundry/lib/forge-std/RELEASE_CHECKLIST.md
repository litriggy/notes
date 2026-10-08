<a id="release-checklist"></a>
# 릴리스 체크리스트

이 체크리스트는 `forge-std` 릴리스 절차를 안내합니다.

<a id="steps"></a>
## 절차

- [ ] `package.json`의 버전 번호를 갱신합니다.
- [ ] 버전 변경을 담은 PR을 열고 병합합니다.
- [ ] 병합한 커밋에 버전 번호로 태그를 붙입니다: `git tag v<X.Y.Z>`
- [ ] 태그를 저장소에 푸시합니다: `git push --tags`
- [ ] 자동 생성한 변경 내역을 포함하고 이름을 `v<X.Y.Z>`로 지정해 새 GitHub 릴리스를 만듭니다.
- [ ] 릴리스 노트 맨 위에 `## Featured Changes` 섹션을 추가합니다.
