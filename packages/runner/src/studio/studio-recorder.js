import { action, computed, observable } from 'mobx'
import { $ } from '@packages/driver'

import eventManager from '../lib/event-manager'

const eventTypes = [
  'click',
  'dblclick',
  'change',
  'keydown',
]

const eventsWithValue = [
  'change',
  'keydown',
  'select',
]

class StudioRecorder {
  @observable testId = null
  @observable isLoading = false
  @observable isActive = false
  @observable _hasStarted = false

  @action setTestId = (testId) => {
    this.testId = testId
  }

  @action startLoading = () => {
    this.isLoading = true
  }

  @computed get isFinished () {
    return this._hasStarted && !this.isActive
  }

  @computed get isOpen () {
    return this.isActive || this.isLoading || this.isFinished
  }

  @action start = (body) => {
    this.isActive = true
    this.isLoading = false
    this.isSaving = false
    this.log = []
    this._currentId = 1
    this._hasStarted = true

    this.attachListeners(body)
  }

  @action stop = () => {
    this.removeListeners()

    this.isActive = false
  }

  @action cancel = () => {
    this.stop()

    this.testId = null
    this._hasStarted = false
    this.isSaving = false
  }

  @action reset = () => {
    this.stop()

    this.log = []
    this._hasStarted = false
    this.isSaving = false
  }

  @action save = () => {
    this.stop()

    this.isSaving = true
  }

  attachListeners = (body) => {
    this._body = body

    eventTypes.forEach((event) => {
      this._body.addEventListener(event, this._recordEvent, {
        capture: true,
        passive: true,
      })
    })
  }

  removeListeners = () => {
    eventTypes.forEach((event) => {
      this._body.removeEventListener(event, this._recordEvent, {
        capture: true,
      })
    })
  }

  removeCommand = (index) => {
    this.log.splice(index, 1)
    this._emitUpdatedLog()
  }

  _getId = () => {
    return `s${this._currentId++}`
  }

  _getCommand = (event, $el) => {
    const tagName = $el.prop('tagName')
    const { type } = event

    if (tagName === 'SELECT' && type === 'change') {
      return 'select'
    }

    if (type === 'keydown') {
      return 'type'
    }

    if (type === 'click' && tagName === 'INPUT') {
      const inputType = $el.prop('type')
      const checked = $el.prop('checked')

      if (inputType === 'radio' || (inputType === 'checkbox' && checked)) {
        return 'check'
      }

      if (inputType === 'checkbox') {
        return 'uncheck'
      }
    }

    return type
  }

  _addModifierKeys = (key, event) => {
    const { altKey, ctrlKey, metaKey, shiftKey } = event

    return `{${altKey ? 'alt+' : ''}${ctrlKey ? 'ctrl+' : ''}${metaKey ? 'meta+' : ''}${shiftKey ? 'shift+' : ''}${key}}`
  }

  _getSpecialKey = (key) => {
    switch (key) {
      case '{':
        return '{'
      case 'ArrowDown':
        return 'downarrow'
      case 'ArrowLeft':
        return 'leftarrow'
      case 'ArrowRight':
        return 'rightarrow'
      case 'ArrowUp':
        return 'uparrow'
      case 'Backspace':
        return 'backspace'
      case 'Delete':
        return 'del'
      case 'Enter':
        return 'enter'
      case 'Escape':
        return 'esc'
      case 'Insert':
        return 'insert'
      case 'PageDown':
        return 'pagedown'
      case 'PageUp':
        return 'pageup'
      default:
        return null
    }
  }

  _getKeyValue = (event) => {
    const { key, altKey, ctrlKey, metaKey } = event

    if (key.length === 1 && key !== '{') {
      // we explicitly check here so we don't accidentally add shift
      // as a modifier key if its not needed
      if (!altKey && !ctrlKey && !metaKey) {
        return key
      }

      return this._addModifierKeys(key.toLowerCase(), event)
    }

    const specialKey = this._getSpecialKey(key)

    if (specialKey) {
      return this._addModifierKeys(specialKey, event)
    }

    return ''
  }

  _getValue = (event, $el) => {
    if (!eventsWithValue.includes(event.type)) {
      return null
    }

    if (event.type === 'keydown') {
      return this._getKeyValue(event)
    }

    return $el.val()
  }

  _shouldRecordEvent = (event, $el) => {
    const tagName = $el.prop('tagName')

    return !(tagName !== 'INPUT' && event.type === 'keydown')
  }

  _recordEvent = (event) => {
    // only capture events sent by the actual user
    if (!event.isTrusted) {
      return
    }

    const $el = $(event.target)

    if (!this._shouldRecordEvent(event, $el)) {
      return
    }

    const Cypress = eventManager.getCypress()

    const selector = Cypress.SelectorPlayground.getSelector($el)

    const action = ({
      id: this._getId(),
      selector,
      command: this._getCommand(event, $el),
      value: this._getValue(event, $el),
    })

    this.log.push(action)

    this._filterLog()

    this._emitUpdatedLog()
  }

  _filterLog = () => {
    const { length } = this.log

    const lastAction = this.log[length - 1]

    if (lastAction.command === 'change') {
      this.log.splice(length - 1)

      return
    }

    if (length > 1) {
      const secondLast = this.log[length - 2]

      if (lastAction.selector === secondLast.selector) {
        if (lastAction.command === 'type' && secondLast.command === 'type') {
          secondLast.value += lastAction.value
          this.log.splice(length - 1)

          return
        }

        if (lastAction.command === 'select' && secondLast.command === 'click') {
          this.log.splice(length - 2, 1)

          return
        }

        if (lastAction.command === 'dblclick' && secondLast.command === 'click' && length > 2) {
          const thirdLast = this.log[length - 3]

          if (lastAction.selector === thirdLast.selector && thirdLast.command === 'click') {
            this.log.splice(length - 3, 2)
          }
        }
      }
    }
  }

  _emitUpdatedLog = () => {
    eventManager.emit('update:studio:log', this.log)
  }
}

export default new StudioRecorder()