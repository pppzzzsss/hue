// Licensed to Cloudera, Inc. under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  Cloudera, Inc. licenses this file
// to you under the Apache License, Version 2.0 (the
// 'License'); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AssistStorageEntry from 'ko/components/assist/assistStorageEntry';

describe('assistStorageEntry.js', () => {
  beforeAll(() => {});

  beforeEach(() => {
    jasmine.Ajax.install();
  });

  afterEach(() => {
    jasmine.Ajax.uninstall();
  });

  it('it should handle domain in ADLS/ABFS', () => {
    jasmine.Ajax.stubRequest(
      '/filebrowser/view=ABFS%3A%2F%2F?format=json&sortby=name&descending=false&pagesize=100&pagenum=1'
    ).andReturn({
      status: 200,
      contentType: 'application/json',
      responseText: JSON.stringify({
        status: 0,
        files: [{ name: 'path' }],
        page: { next_page_number: 0 }
      })
    });
    AssistStorageEntry.getEntry('abfs://test.com/path').always(entry => {
      expect(entry.path).toBe('/path');
    });
    AssistStorageEntry.getEntry('abfs://path').always(entry => {
      expect(entry.path).toBe('/path');
    });
    AssistStorageEntry.getEntry('abfs://path@test.com').always(entry => {
      expect(entry.path).toBe('/path');
    });
    jasmine.Ajax.stubRequest(
      '/filebrowser/view=ABFS%3A%2F%2F?format=json&sortby=name&descending=false&pagesize=100&pagenum=1'
    ).andReturn({
      status: 200,
      contentType: 'application/json',
      responseText: JSON.stringify({
        status: 0,
        files: [{ name: 'p1' }],
        page: { next_page_number: 0 }
      })
    });
    jasmine.Ajax.stubRequest(
      '/filebrowser/view=ABFS%3A%2F%2Fp1?format=json&sortby=name&descending=false&pagesize=100&pagenum=1'
    ).andReturn({
      status: 200,
      contentType: 'application/json',
      responseText: JSON.stringify({
        status: 0,
        files: [{ name: 'p2' }],
        page: { next_page_number: 0 }
      })
    });
    AssistStorageEntry.getEntry('abfs://p1@test.com/p2').always(entry => {
      expect(entry.path).toBe('/p1/p2');
    });
  });
});
