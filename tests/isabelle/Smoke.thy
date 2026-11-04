theory Smoke
  imports Main
begin

lemma identity: "P \<Longrightarrow> P"
proof -
  assume p: P
  show P using p by assumption
qed

lemma reverse_twice: "rev (rev xs) = xs"
  by simp

lemma cartesian_member: "(x, y) \<in> A \<times> B \<longleftrightarrow> x \<in> A \<and> y \<in> B"
  by simp

end
