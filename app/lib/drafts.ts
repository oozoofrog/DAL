export type Draft={body:string;kind:'reply'|'rerequest'};export type Drafts=Record<string,Draft>;
export function updateDraft(drafts:Drafts,id:string,patch:Partial<Draft>):Drafts{return{...drafts,[id]:{...(drafts[id]??{body:'',kind:'reply'}),...patch}}}
export function clearSubmittedDraft(drafts:Drafts,id:string,body:string,kind:Draft['kind']):Drafts{const draft=drafts[id];if(!draft||draft.body!==body||draft.kind!==kind)return drafts;return{...drafts,[id]:{body:'',kind:'reply'}}}
