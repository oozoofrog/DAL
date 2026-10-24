import { DatabaseSync } from 'node:sqlite';import {readFileSync,readdirSync} from 'node:fs';import {fileURLToPath} from 'node:url';
export class SqliteD1 {
  sqlite = new DatabaseSync(':memory:');
  constructor(){const directory=new URL('../drizzle/',import.meta.url);for(const file of readdirSync(fileURLToPath(directory)).filter(f=>f.endsWith('.sql')).sort())this.sqlite.exec(readFileSync(new URL(file,directory),'utf8'));}
  prepare(sql:string){ const db=this.sqlite; let args:any[]=[]; const api:any={ bind(...values:any[]){args=values;return api}, async all(){return {results:db.prepare(sql).all(...args)}}, async first(){return db.prepare(sql).get(...args)??null}, async run(){return db.prepare(sql).run(...args)}, _run(){return db.prepare(sql).run(...args)} };return api; }
  async batch(statements:any[]){this.sqlite.exec('BEGIN');try{const result=statements.map(s=>s._run());this.sqlite.exec('COMMIT');return result;}catch(e){this.sqlite.exec('ROLLBACK');throw e;}}
}
