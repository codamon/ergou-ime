// ergou-ime — SPDX-License-Identifier: GPL-3.0-only
// Drives librime with the bundled ergou_wubi schema and prints menus/commits.
// usage: harness <shared_dir> <user_dir> <keys...>   ("_" = space, "!" = clear,
//        "<" ">" = Left/Right, "^" "~" = Up/Down)
// ERGOU_HARNESS_HORIZONTAL=1 sets _horizontal like ErgouIME (RimeEngine.swift).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <rime_api.h>
static RimeApi *api;
static void show(RimeSessionId s, const char *label) {
  RIME_STRUCT(RimeCommit, commit);
  if (api->get_commit(s, &commit)) { printf("  [%s] COMMIT %s\n", label, commit.text); api->free_commit(&commit); }
  RIME_STRUCT(RimeContext, ctx);
  if (api->get_context(s, &ctx)) {
    printf("  [%s] input=%s menu:", label, ctx.composition.preedit ? ctx.composition.preedit : "");
    for (int i = 0; i < ctx.menu.num_candidates; i++)
      printf(" %d.%s%s%s", i + 1, ctx.menu.candidates[i].text,
             ctx.menu.candidates[i].comment ? "(" : "", ctx.menu.candidates[i].comment ? ctx.menu.candidates[i].comment : "");
    printf("%s", ctx.menu.num_candidates ? "" : " (none)");
    if (ctx.menu.num_candidates)
      printf("  [page %d, highlight %d]", ctx.menu.page_no + 1, ctx.menu.highlighted_candidate_index + 1);
    printf("\n");
    api->free_context(&ctx);
  }
}
int main(int argc, char **argv) {
  api = rime_get_api();
  RIME_STRUCT(RimeTraits, t);
  t.shared_data_dir = argv[1]; t.user_data_dir = argv[2];
  t.app_name = "rime.ergou.harness"; t.min_log_level = 1; t.log_dir = argv[2];
  api->setup(&t); api->initialize(&t);
  if (api->start_maintenance(1)) api->join_maintenance_thread();
  RimeSessionId s = api->create_session();
  const char *h = getenv("ERGOU_HARNESS_HORIZONTAL");
  if (h && *h == '1') api->set_option(s, "_horizontal", 1);
  char sid[64] = {0}; api->get_current_schema(s, sid, sizeof sid); printf("schema=%s\n", sid);
  for (int a = 3; a < argc; a++) {
    printf("> %s\n", argv[a]);
    for (const char *p = argv[a]; *p; p++) {
      if (*p == '!') { api->clear_composition(s); continue; }
      int key = *p == '_' ? ' ' : *p == '<' ? 0xff51 : *p == '>' ? 0xff53
              : *p == '^' ? 0xff52 : *p == '~' ? 0xff54 : *p;
      api->process_key(s, key, 0);
    }
    show(s, argv[a]);
    api->clear_composition(s);
  }
  api->destroy_session(s); api->finalize();
  return 0;
}
