import test from 'node:test';import assert from 'node:assert/strict';
import { updateDraft, clearSubmittedDraft } from '../app/lib/drafts.ts';
test('thread drafts never move between conversations',()=>{let drafts=updateDraft({},'A',{body:'A 요청',kind:'rerequest'});drafts=updateDraft(drafts,'B',{body:'B 답글'});assert.equal(drafts.A.body,'A 요청');assert.equal(drafts.B.body,'B 답글');});
test('inflight reply clears only submitted thread when unchanged',()=>{const drafts={A:{body:'보낸 글',kind:'reply' as const},B:{body:'작성 중',kind:'rerequest' as const}};const next=clearSubmittedDraft(drafts,'A','보낸 글','reply');assert.equal(next.A.body,'');assert.equal(next.B.body,'작성 중');assert.equal(next.B.kind,'rerequest');});
test('new edits during inflight request survive completion',()=>{const drafts={A:{body:'새로 작성한 글',kind:'reply' as const}};assert.equal(clearSubmittedDraft(drafts,'A','예전 글','reply').A.body,'새로 작성한 글');});
