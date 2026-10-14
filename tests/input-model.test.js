const assert = require('node:assert/strict')
const test = require('node:test')
const M = require('../InputModel.js')
test('insert and replace selection preserve cursor', () => {
  assert.deepEqual(M.insert('abcd', 2, 2, 'X', 8), {text:'abXcd',cursor:3,anchor:3})
  assert.deepEqual(M.insert('abcd', 4, 0, 'X', 8), {text:'X',cursor:1,anchor:1})
})
test('limits reject the entire insertion and forbid multiline/control text', () => {
  assert.equal(M.insert('abcd', 4, 4, 'X', 4), null)
  assert.equal(M.insert('abcd', 4, 0, 'X'.repeat(5), 4), null)
  for (const t of ['x\ny','x\ry','x\ty','x\0y']) assert.equal(M.insert('',0,0,t,100),null)
})
test('backspace, forward delete and selected deletion', () => {
  assert.deepEqual(M.remove('abcd',2,2,true), {text:'acd',cursor:1,anchor:1})
  assert.deepEqual(M.remove('abcd',2,2,false), {text:'abd',cursor:2,anchor:2})
  assert.deepEqual(M.remove('abcd',1,3,true), {text:'ad',cursor:1,anchor:1})
  assert.deepEqual(M.remove('',0,0,true), {text:'',cursor:0,anchor:0})
})
test('cursor and deletion preserve UTF-16 surrogate pairs', () => {
  assert.equal(M.previous('a😀b',3),1)
  assert.equal(M.next('a😀b',1),3)
  assert.deepEqual(M.remove('a😀b',3,3,true),{text:'ab',cursor:1,anchor:1})
})
